# Pitfalls Research

**Domain:** Splitting shared-state jackpot into independent main + bonus drawings (Solidity, existing VRF system)
**Researched:** 2026-04-11
**Confidence:** HIGH (analysis derived from actual contract code, not web sources)

## Critical Pitfalls

### Pitfall 1: Entropy Correlation Between Main and Bonus Trait Rolls

**What goes wrong:**
Both main and bonus drawings derive traits from the same VRF word via `_rollWinningTraits(randWord)`. `JackpotBucketLib.getRandomTraits` uses bits [0:5], [6:11], [12:17], [18:23] of `randWord`. `_applyHeroOverride` uses bits [0:2] or [3:5] or [6:8] or [9:11] depending on hero quadrant. If both main and bonus call `_rollWinningTraits(randWord)` with the identical `randWord`, their base traits are identical (hero override may differ only if hero state changes between calls, which it cannot within a single tx). Result: every bonus drawing has traits perfectly correlated with main. Same trait buckets win in both drawings -- no independence.

**Why it happens:**
The existing trait roll function `_rollWinningTraits` is deterministic on `randWord` alone. Adding a second call with the same input produces the same output. Developers see two separate function calls and assume independence.

**How to avoid:**
Bonus trait roll must use a domain-separated entropy. Derive a `bonusRandWord` via `keccak256(abi.encodePacked(randWord, BONUS_TRAIT_TAG))` where `BONUS_TRAIT_TAG` is a unique constant (e.g., `keccak256("bonus-traits")`). Then call `_rollWinningTraits(bonusRandWord)`. This produces 4 independent trait selections from VRF-quality entropy while preserving determinism.

Critically, the hero override must be preserved -- the spec says "hero symbol preserved" for bonus. So `_applyHeroOverride` runs on the bonus traits too, but using `bonusRandWord` for the color component. The hero symbol itself comes from `_topHeroSymbol(day)` which is global state, so both drawings get the same hero symbol (correct), but in independently-rolled color+quadrant contexts.

**Warning signs:**
- Bonus trait packed value equals main trait packed value in logs
- `_rollWinningTraits` called twice with identical argument in same tx
- No `keccak256`-based domain separation constant for the bonus path

**Phase to address:**
Implementation phase (code change). Must be part of the first commit that adds the bonus trait roll.

---

### Pitfall 2: Stale `dailyJackpotTraitsPacked` Carryover to Bonus Path

**What goes wrong:**
The current system stores winning traits in `dailyJackpotTraitsPacked` via `_syncDailyWinningTraits` for cross-call reuse (Phase 1 ETH -> Phase 2 coin+tickets). The store writes `[traits(32) | level(24) | day(32)]` = 88 bits total. If the bonus drawing reuses this storage to read "the day's winning traits" for its own ticket distribution, it reads the main traits, not the independently-rolled bonus traits.

The specific danger site is `payDailyCoinJackpot` (purchase phase path, L1676-1683): it calls `_loadDailyWinningTraits(lvl, questDay)` and falls through to the cached main traits. If the bonus BURNIE drawing is intended to use bonus traits for near-future winner selection, but reads from `dailyJackpotTraitsPacked`, it silently uses main traits.

**Why it happens:**
`dailyJackpotTraitsPacked` is a single shared storage slot. The existing architecture assumes one set of winning traits per day. Adding a second independent set requires either a second storage slot or an event-only approach.

**How to avoid:**
The spec says "Event emitted for bonus winning traits (no storage)." This is the correct approach -- roll bonus traits, emit an event, and pass them through function parameters within the same call. Never write bonus traits to `dailyJackpotTraitsPacked`. The main traits in that storage should remain untouched.

For the jackpot phase path (where Phase 1 stores traits for Phase 2 reuse), the bonus traits must either:
1. Be stored in a separate packed slot (e.g., `dailyBonusTraitsPacked`), or
2. Be re-derived from `randWord` with the bonus domain separator in Phase 2 (since `randWord` is already available as `rngWordCurrent`).

Option 2 is cheaper (no extra SSTORE) and deterministic -- re-rolling from domain-separated entropy produces the same bonus traits in Phase 2 as Phase 1.

**Warning signs:**
- Bonus ticket distribution calling `_loadDailyWinningTraits` or reading `dailyJackpotTraitsPacked`
- Only one `_syncDailyWinningTraits` call per day despite two independent drawings
- Bonus events emitting trait IDs that match main trait IDs

**Phase to address:**
Implementation phase. Verify in delta audit.

---

### Pitfall 3: Off-by-One in Bonus Target Level Range Shift

**What goes wrong:**
The current near-future BURNIE target is `[lvl, lvl+4]` via `_selectDailyCoinTargetLevel` which returns `lvl + uint24(entropy % 5)`. The spec narrows this to `[lvl+1, lvl+4]` for bonus (4 levels instead of 5). A naive change `entropy % 4 + 1` looks correct but has two subtle risks:

1. **Range calculation:** `entropy % 4` produces `{0,1,2,3}`, so `lvl + 1 + (entropy % 4)` = `{lvl+1, lvl+2, lvl+3, lvl+4}`. This is correct. But if someone writes `lvl + (entropy % 4) + 1` without the `uint24` cast, the addition order could matter for very large entropy values (though in practice uint256 mod 4 is safe).

2. **Carryover source range collision:** The existing carryover source also selects from `[lvl+1, lvl+4]` via `(entropy % DAILY_CARRYOVER_MAX_OFFSET) + 1` at L389-398. If bonus target selection uses the same range, the carryover source level and bonus target level could collide, meaning the same future-level ticket pool is sampled twice by different jackpot paths in the same transaction. This is not a bug per se (tickets allow duplicate winners), but it concentrates rewards on one level's holders rather than spreading across the near-future range.

3. **Empty bucket at level 0:** At level 0, `lvl+1 = 1`. Tickets for level 1 may not exist yet (no purchases at level 1). The current `[lvl, lvl+4]` includes current-level tickets as a fallback. The narrowed `[lvl+1, lvl+4]` removes this fallback. At level 0, all bonus target levels may have zero tickets, silently dropping the entire bonus budget.

**Why it happens:**
Off-by-one errors in range definitions are ubiquitous. The shift from inclusive-current to exclusive-current changes the edge case at level 0.

**How to avoid:**
- Verify the range produces exactly `{lvl+1, lvl+2, lvl+3, lvl+4}` via unit test with boundary values
- Add explicit test for level 0: confirm bonus traits roll succeeds (even if no winners found -- budget should not be lost)
- Document the deliberate difference between main target range `[lvl, lvl+4]` and bonus target range `[lvl+1, lvl+4]`
- Ensure the bonus target function is a new function (e.g., `_selectBonusCoinTargetLevel`) not a modification of `_selectDailyCoinTargetLevel` which is still used by the main drawing

**Warning signs:**
- Bonus BURNIE jackpot at level 0 produces zero winners and budget disappears
- `entropy % 5` still present in bonus path (means range was not narrowed)
- `entropy % 3` in bonus path (too narrow -- only `[lvl+1, lvl+3]`)

**Phase to address:**
Implementation phase. Unit test in the test phase.

---

### Pitfall 4: Gas Regression From Double Trait Rolling

**What goes wrong:**
Adding a second `_rollWinningTraits` call per daily jackpot adds gas. The function itself is cheap (~500 gas for bit extraction + hero override read). But the downstream cost is in `_computeBucketCounts` which reads `traitBurnTicket[lvl][trait].length` for 4 traits -- 4 cold SLOADs (~8,400 gas) per bucket computation. If the bonus drawing calls `_computeBucketCounts` against a different level's trait buckets (which it must, since bonus targets `[lvl+1, lvl+4]`), that is 4 more cold SLOADs at a new level.

The existing gas ceiling analysis (v15.0) showed `advanceGame` at 7,023,530 gas with a 1.99x margin against a 14M ceiling. Each additional cold SLOAD set costs ~8,400 gas. But the real concern is the bonus BURNIE distribution loop: `_awardDailyCoinToTraitWinners` iterates up to `DAILY_COIN_MAX_WINNERS = 50` winners with one `coinflip.creditFlip` external call each (~5,000 gas per call). Doubling this for bonus means up to 100 `creditFlip` calls total.

At 50 bonus winners * 5,000 gas = 250,000 gas additional. Current margin is ~7M gas (14M - 7M). The 250K addition is 3.6% of the remaining headroom -- safely within margin, but it compounds with other changes.

**Why it happens:**
Each jackpot path (main ETH, main coin, bonus coin, carryover tickets, daily tickets) has its own loop. Adding a path adds a loop. Gas accumulates linearly.

**How to avoid:**
- Measure actual gas delta after implementation (not just estimate)
- The bonus BURNIE distribution should reuse `_awardDailyCoinToTraitWinners` with bonus traits at the bonus target level -- no new function needed, just different parameters
- Consider whether bonus BURNIE distribution can share the `creditFlipBatch` pattern used by `_awardFarFutureCoinJackpot` (L1855) to reduce per-winner external call overhead
- If gas is tight, the bonus max winners cap can be lower than the main cap (e.g., 30 instead of 50)

**Warning signs:**
- `advanceGame` gas exceeds 10M in worst-case Foundry test
- New `for` loop with external calls inside the bonus path
- No `creditFlipBatch` usage in the bonus distribution

**Phase to address:**
Implementation phase (structure the code for efficiency). Gas audit phase (measure and verify margin).

---

### Pitfall 5: Carryover Ticket Distribution Reading Main Traits Instead of Bonus Traits

**What goes wrong:**
The spec says "Carryover ticket distribution uses bonus traits (draws from future-level tickets)." Currently, carryover tickets at L608-621 in `payDailyJackpotCoinAndTickets` call `_distributeTicketJackpot(sourceLevel, ..., winningTraitsPacked, ...)` where `winningTraitsPacked` is the main traits loaded from `dailyJackpotTraitsPacked` at L562. If carryover should use bonus traits, but the code still reads from the shared storage that holds main traits, carryover winners are selected by main traits instead of bonus traits.

This is particularly insidious because carryover ticket distribution draws winners from `sourceLevel` (a near-future level), and the ticket pool at that level has its own trait distribution. Using main traits (which were rolled for current-level ticket pools) to select winners from a future-level pool could systematically favor or disadvantage certain trait buckets based on how trait distributions differ between current and future levels.

**Why it happens:**
The existing carryover path reads `winningTraitsPacked` from Phase 1 storage. It is easy to miss that this specific use site needs bonus traits while other use sites in the same function need main traits.

**How to avoid:**
- In `payDailyJackpotCoinAndTickets`, derive bonus traits from `randWord` using the domain separator (re-derivation approach from Pitfall 2)
- Pass bonus `winningTraitsPacked` to the carryover `_distributeTicketJackpot` call
- Pass main `winningTraitsPacked` to the daily ticket `_distributeTicketJackpot` call (L596-606, unchanged)
- Add explicit variable names: `mainTraitsPacked` vs `bonusTraitsPacked` to prevent confusion

**Warning signs:**
- Single `winningTraitsPacked` variable used for both daily ticket and carryover ticket distribution
- No bonus domain separator derivation in `payDailyJackpotCoinAndTickets`
- Carryover ticket winners have identical trait distribution to daily ticket winners in test logs

**Phase to address:**
Implementation phase. Delta audit must explicitly verify which traits are used by which distribution path.

---

### Pitfall 6: RNG Commitment Window -- Second Trait Roll Does Not Widen the Window

**What goes wrong:**
Misunderstanding that adding a second trait roll creates a new RNG commitment window vulnerability. It does not, because both trait rolls derive from the same `randWord` in the same transaction. The VRF commitment window is between VRF request (when the player's tickets are already committed) and VRF fulfillment (when `randWord` is delivered). A second derivation from the same `randWord` does not create a new window -- it operates within the same fulfillment.

However, the real risk is if the bonus trait roll is moved to a separate transaction (e.g., a separate `advanceGame` call). If bonus traits were rolled in a later call with a different VRF word, tickets committed before the first VRF request could be evaluated against a VRF word requested after the player knew the main drawing results. This is the actual commitment window concern.

**Why it happens:**
Developers may split bonus processing into a separate call for gas reasons (similar to the existing Phase 1/Phase 2 split for ETH vs coin+tickets). If that separate call uses a different VRF word, the commitment window widens.

**How to avoid:**
- Both main and bonus trait rolls MUST use the same `randWord` from the same VRF fulfillment
- If bonus processing is split across calls (like the existing Phase 1/Phase 2 split), bonus traits must be re-derived from `rngWordCurrent` (the stored VRF word), not from a new VRF request
- The existing pattern at L562-563 is safe: Phase 2 reads `randWord` which is `rngWordCurrent` from Phase 1. The bonus path must follow this same pattern
- NEVER introduce a new `requestRandomWords` for the bonus drawing

**Warning signs:**
- Bonus path references `rngWordNext` or any VRF word other than the current daily word
- New `requestRandomWords` call associated with bonus drawing
- Bonus processing requires its own `rngLockedFlag` cycle

**Phase to address:**
Implementation phase (architecture decision). RNG audit phase (formal verification that commitment window is unchanged).

---

### Pitfall 7: Event Ordering and Indexing When Two Drawings Occur in Same Transaction

**What goes wrong:**
Main and bonus drawings emit events in the same transaction. Currently, `JackpotBurnieWin` events (L1762) are emitted for BURNIE winners with `(winner, level, traitId, amount, ticketIndex)` where `level` and `traitId` are indexed. If both main and bonus BURNIE drawings emit `JackpotBurnieWin` events, the log consumer cannot distinguish which event belongs to which drawing. A frontend filtering by `traitId` would conflate main-trait winners with bonus-trait winners.

Similarly, `JackpotTicketWin` events (L992) have `(winner, ticketLevel, traitId, ticketCount, sourceLevel, ticketIndex)`. If carryover tickets (now using bonus traits) and daily tickets (using main traits) both emit `JackpotTicketWin`, the `traitId` indexed field could match either drawing's traits, making log analysis ambiguous.

**Why it happens:**
The existing event schema assumes one set of winning traits per day. Adding a second drawing doubles event emission without distinguishing the source.

**How to avoid:**
The spec says "Event emitted for bonus winning traits (no storage)." This implies a new event type. Options:

1. **New event for bonus BURNIE wins:** `BonusBurnieWin(winner, level, traitId, amount, ticketIndex)` -- cleanest separation
2. **Add a `bool isBonus` field to existing events** -- minimal schema change but wastes an unindexed field slot on all main events
3. **Separate event for bonus traits themselves:** `BonusWinningTraits(uint32 packed, uint24 level)` emitted once per day, then existing events carry the trait IDs that consumers can cross-reference

Option 1 is recommended. It follows the existing pattern (separate events for separate drawing types: `JackpotEthWin`, `JackpotBurnieWin`, `JackpotTicketWin`, `FarFutureCoinJackpotWinner` are all distinct). A `BonusBurnieWin` event plus a `BonusWinningTraits` event-only emission provides complete auditability without storage.

For carryover tickets, if they now use bonus traits, the `JackpotTicketWin` event should include enough context (the `sourceLevel` field already present) to differentiate, OR a new `BonusTicketWin` event should be used.

**Warning signs:**
- Same event signature used for both main and bonus winners
- Log consumers unable to reconstruct which drawing a particular win came from
- No new event type defined for bonus outcomes
- `traitId` in existing events could be from either main or bonus traits

**Phase to address:**
Implementation phase (event definitions). Frontend integration should verify log parsing handles new events.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Reuse `_awardDailyCoinToTraitWinners` for bonus without new function | Less code duplication | Harder to tune bonus-specific behavior (different max winners, different budget split) | Acceptable for initial implementation if parameters are passed in |
| Store bonus traits in `dailyJackpotTraitsPacked` upper bits | No new storage slot | Bit packing complexity, harder to audit, more error-prone shifts/masks | Never -- spec says event-only for bonus traits |
| Modify `_selectDailyCoinTargetLevel` to accept a range parameter | One function for both ranges | Every call site must pass correct range, easy to pass wrong one | Never -- two tiny functions is clearer |
| Skip gas measurement after adding bonus path | Faster development | Potential silent gas regression past safety margin | Never -- gas ceiling is a hard constraint (14M block limit) |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `dailyJackpotTraitsPacked` storage | Reading cached main traits for bonus path | Re-derive bonus traits from `keccak256(randWord, BONUS_TAG)` in Phase 2 |
| `_syncDailyWinningTraits` | Calling it with bonus traits (overwrites main traits) | Only sync main traits to storage; bonus traits are event-only and parameter-passed |
| `payDailyCoinJackpot` (purchase phase) | Modifying `_selectDailyCoinTargetLevel` range from `%5` to `%4+1` | Create `_selectBonusCoinTargetLevel` with `%4+1` range; keep original function unchanged |
| `_computeBucketCounts` level parameter | Passing current level when bonus should sample future level | Bonus must pass the bonus target level (from `[lvl+1, lvl+4]`) to `_computeBucketCounts` |
| Carryover source tag entropy | Using `DAILY_CARRYOVER_SOURCE_TAG` for bonus target selection too | Use a distinct `BONUS_TARGET_TAG` constant for bonus level selection entropy |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Double `coinflip.creditFlip` loop (main + bonus) | Gas spikes on high-winner-count days | Use `creditFlipBatch` for bonus distribution or share batch with main | When main + bonus winners exceed ~200 total |
| Cold SLOADs on bonus target level trait buckets | Additional ~8,400 gas per bonus drawing | Acceptable cost; verify stays within gas ceiling | If combined with other gas-adding features |
| `_randTraitTicket` calls doubled (main + bonus traits at different levels) | 8 `_randTraitTicket` calls instead of 4 | Each call is bounded by `MAX_BUCKET_WINNERS`; gas scales with winner count, not call count | Not a realistic break point given current margins |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Bonus traits derived from same entropy as main traits (no domain separation) | Correlated drawings -- same holders win both, undermining "independent" claim | `keccak256(randWord, BONUS_TRAIT_TAG)` domain separation |
| Bonus VRF word from a different request than main | Commitment window vulnerability -- tickets committed before bonus VRF request | Both drawings must use same `rngWordCurrent` |
| Modifying `_rollWinningTraits` signature or behavior | Regression in main drawing trait roll across all existing paths | Bonus must call `_rollWinningTraits` with bonus-derived entropy, not modify the function |
| Bonus budget drawn from wrong pool | ETH accounting error (draining currentPool for BURNIE, or futurePool for main ETH) | Bonus BURNIE budget comes from `_calcDailyCoinBudget` -- a virtual BURNIE amount not backed by ETH. Verify no ETH pool deduction for bonus. |
| Carryover tickets deposited at wrong level | Tickets created at level N but backed by level N+1 prices, or vice versa | Carryover `_queueTickets` target level must match the `nextPrizePool` backing |

## "Looks Done But Isn't" Checklist

- [ ] **Bonus trait roll:** Verify `_rollWinningTraits(bonusRandWord)` uses domain-separated entropy, not raw `randWord`
- [ ] **Hero override in bonus:** Verify `_applyHeroOverride` is called on bonus traits (spec: "hero symbol preserved")
- [ ] **Carryover uses bonus traits:** Verify `_distributeTicketJackpot` for carryover passes bonus traits, not main traits
- [ ] **Daily ticket uses main traits:** Verify `_distributeTicketJackpot` for daily tickets passes main traits (unchanged)
- [ ] **Main ETH jackpot unchanged:** Verify `payDailyJackpot` jackpot-phase ETH path still uses main traits exclusively
- [ ] **Main 20% ticket distribution unchanged:** Verify daily lootbox/ticket budget still uses main traits at `lvl+1`
- [ ] **Bonus target range is [lvl+1, lvl+4]:** Verify `entropy % 4 + 1` not `entropy % 5`
- [ ] **Main coin target range unchanged at [lvl, lvl+4]:** Verify `_selectDailyCoinTargetLevel` is unmodified
- [ ] **Event emitted for bonus winning traits:** Verify a `BonusWinningTraits` or equivalent event fires
- [ ] **Event emitted for bonus BURNIE winners:** Verify distinct event type from `JackpotBurnieWin`
- [ ] **No bonus traits written to `dailyJackpotTraitsPacked`:** Verify `_syncDailyWinningTraits` is NOT called with bonus traits
- [ ] **Gas ceiling still within 2x margin:** Verify worst-case gas stays below 10M
- [ ] **Early-bird lootbox unchanged:** Verify early-bird path does not reference bonus traits
- [ ] **Level 0 bonus drawing:** Verify bonus target `[1, 4]` handles empty trait buckets gracefully (no lost budget)
- [ ] **Purchase phase bonus coin jackpot:** Verify `payDailyCoinJackpot` correctly separates main and bonus paths
- [ ] **Jackpot phase bonus coin:** Verify `payDailyJackpotCoinAndTickets` correctly separates main coin and bonus coin paths

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Correlated traits (no domain separation) | LOW | Add `BONUS_TRAIT_TAG` constant, change one `_rollWinningTraits` call. No storage migration. |
| Stale traits in carryover | LOW | Change which `winningTraitsPacked` variable is passed to carryover `_distributeTicketJackpot`. No storage migration. |
| Wrong target range | LOW | Change `% 5` to `% 4 + 1` in bonus target function. No storage migration. |
| Gas regression past ceiling | MEDIUM | Reduce bonus max winners, add `creditFlipBatch`, or split into separate `advanceGame` call (but must use same VRF word). |
| Event ambiguity (no new event type) | LOW | Add new event type and emit it. Existing events unchanged. Frontend must be updated. |
| Commitment window violation (separate VRF) | HIGH | Architectural rework to ensure bonus uses same VRF word. If deployed with separate VRF, requires contract redeployment. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Entropy correlation | Implementation | Unit test: main traits != bonus traits for same `randWord` |
| Stale trait storage | Implementation | Code review: grep for `dailyJackpotTraitsPacked` reads in bonus path |
| Off-by-one target range | Implementation + Test | Unit test: bonus target range is exactly `{lvl+1, lvl+2, lvl+3, lvl+4}` for all entropy values |
| Gas regression | Gas Audit | Foundry gas profiling: worst-case `advanceGame` with bonus active |
| Carryover trait confusion | Implementation | Code review: variable names `mainTraits` vs `bonusTraits` at each call site |
| RNG commitment window | RNG Audit | Formal trace: verify bonus `randWord` == main `randWord` == `rngWordCurrent` |
| Event ordering | Implementation | Integration test: parse logs, verify main and bonus events distinguishable |

## Sources

- Direct code analysis of `DegenerusGameJackpotModule.sol` (current contract, lines referenced above)
- `JackpotBucketLib.getRandomTraits` bit extraction pattern (L281-286)
- `_applyHeroOverride` hero symbol override (L1537-1564)
- `_syncDailyWinningTraits` / `_loadDailyWinningTraits` storage pattern (L1869-1886)
- `_selectDailyCoinTargetLevel` range: `lvl + entropy % 5` (L1706)
- Carryover source range: `(entropy % DAILY_CARRYOVER_MAX_OFFSET) + 1` = `[1, 4]` (L389-398)
- `payDailyJackpotCoinAndTickets` Phase 2 trait reuse from storage (L561-562)
- Gas ceiling analysis: v15.0 Phase 166 (7,023,530 gas, 1.99x margin)
- RNG commitment window audit: v3.8 Phases 68-72 (51/51 SAFE)
- F-25-07: `rngLockedFlag` asymmetry finding (index advance isolation for lootbox)
- v25.0 regression check: all 31 items verified, 0 regressions

---
*Pitfalls research for: v26.0 Bonus Jackpot Split (independent trait rolls)*
*Researched: 2026-04-11*
