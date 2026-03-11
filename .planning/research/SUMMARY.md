# Project Research Summary

**Project:** Degenerus Protocol — Always-Open Purchases
**Domain:** On-chain game contract — double-buffered ticket queues, packed prize pool storage, prize pool freeze/unfreeze mechanics
**Researched:** 2026-03-11
**Confidence:** HIGH

## Executive Summary

This milestone adds always-open purchase infrastructure to the existing Degenerus Protocol delegatecall-module system. The core problem: ticket purchases currently revert while daily RNG processing is active (`rngLockedFlag`). The solution is a two-part system — a double-buffered ticket queue (so purchases land in a write slot that is never touched by the processing loop) plus a prize pool freeze/unfreeze mechanism (so jackpot payout amounts are locked against the pre-purchase-cycle pool value). Both systems interact with a shared storage layout that all delegatecall modules must see identically, making storage discipline the single most important constraint on the entire implementation.

The recommended approach is to treat this as a bottom-up implementation: storage changes first, helper functions second, module migrations third, and the `advanceGame` rewrite last. No new external dependencies are needed. All patterns (bit-23 key encoding for the double buffer, uint128 packing for prize pools, freeze-branch at purchase-path pool additions) are either already used in the codebase or are established EVM idioms. The implementation plan (`audit/PLAN-ALWAYS-OPEN-PURCHASES.md`) is implementation-ready — the roadmap should reflect its dependency ordering rather than reordering it.

The critical risks are storage layout integrity (one wrong byte in Slot 1 silently corrupts all module delegatecalls), unfreeze placement in the `advanceGame` state machine (three correct sites, every incorrect site either loses pending ETH or inflates jackpot payouts), and migration completeness (101 occurrences of `nextPrizePool`/`futurePrizePool` across 11 files must all move to packed helpers). Each risk has a mechanical verification: `forge inspect`, a grep for old variable names, and a freeze-state integration test covering all purchase paths. Build with clean artifacts after every storage change.

## Key Findings

### Recommended Stack

No new dependencies are added. The milestone operates entirely within the existing stack: Solidity 0.8.34 with `via_ir = true` and `optimizer_runs = 2` (Foundry 1.5.1), OpenZeppelin 5.4.0 as reference only, and forge-std for testing. The IR pipeline is load-bearing — it handles stack pressure from multiple uint128 locals in functions like `_unfreezePool` and inlines small `internal view` helpers (`_tqWriteKey`/`_tqReadKey`) to zero runtime cost.

**Core technologies:**
- Solidity 0.8.34: locked per project; auto-overflow checks, custom errors, named returns
- Foundry `via_ir = true`: inlines key helpers, handles stack depth — do not disable
- Raw bitwise shift/mask: `uint256(x) << 128 | uint256(y)` — canonical EVM packing, no library needed
- forge-std / Hardhat: existing test suites; both needed for invariant fuzz and JS integration tests

**Critical version notes:**
- Always `forge clean` before building after storage layout changes — incremental builds with stale module artifacts are a correctness hazard, not just a performance issue
- `ticketWriteSlot` must be `uint8` (not `bool`) to enable the XOR toggle idiom: `ticketWriteSlot ^= 1`

### Expected Features

All v1 features are non-separable in production — the system is only safe to deploy as a complete atomic changeset. Partial deployment (e.g., removing the lock without write slot isolation) introduces invariant violations worse than the current lock.

**Must have (table stakes — all P1, all required for launch):**
- Remove `rngLockedFlag` purchase reverts — the UX goal; must be the last step, not the first
- Write slot isolation (bit-23 key encoding + all `_queueTickets*` updated) — prerequisite for safe lock removal
- Read slot drain gate in `_swapTicketSlot` (`ReadSlotNotDrained` revert) — orphan prevention
- Prize pool freeze + pending accumulators — jackpot integrity during concurrent purchases
- `ticketsFullyProcessed` flag — gates jackpot logic until queue is drained
- Revised `advanceGame` flow — mid-day path, drain gates, `_swapAndFreeze`, `_unfreezePool` call sites
- Slot 1 storage additions: `ticketWriteSlot` (uint8), `ticketsFullyProcessed` (bool), `prizePoolFrozen` (bool)

**Should have (add after daily path is validated stable):**
- Mid-day queue swap path (440-entry threshold trigger) — throughput, not correctness; system is correct without it
- Bounty tuning for mid-day `advanceGame` calls

**Defer (v2+):**
- Full gas optimization pass beyond packed pools
- Frontend UX updates reflecting always-open state
- DGNRS token changes (already soulbound, explicitly out of scope)

### Architecture Approach

The system uses a delegatecall module pattern where `DegenerusGame.sol` owns all state and dispatches to stateless modules. Every module inherits `DegenerusGameStorage`, which is the single source of truth for slot layout — changes to that file affect all modules simultaneously, and stale compiled artifacts from any module are silently incorrect.

**Major components and change scope:**
1. **DegenerusGameStorage** — PRIMARY: 3 new Slot 1 flags, replace `nextPrizePool`+`futurePrizePool` with `prizePoolsPacked`, add `prizePoolPendingPacked`, add all key/swap/freeze/unfreeze helpers
2. **DegenerusGameAdvanceModule** — PRIMARY: full rewrite of `advanceGame` — mid-day path, daily gate, `_swapAndFreeze` at RNG request, `_unfreezePool` at three designated unlock points
3. **DegenerusGameJackpotModule** — MODIFIED: migrate to packed pool helpers, update queue accesses to read-key
4. **DegenerusGameMintModule** — MODIFIED: remove 2 `rngLockedFlag` reverts, add freeze branch to lootbox pool split, update future ticket processing to read-key
5. **DegenerusGame.sol, WhaleModule, DegeneretteModule** — MODIFIED: add freeze branch to all purchase-path pool additions (9 call sites total)
6. **EndgameModule, DecimatorModule** — MODIFIED: migrate pool reads/writes to packed helpers only (no freeze branch — game logic, not purchase paths)

**Key patterns:**
- Freeze branch only at purchase-driven pool additions; never at game-logic pool mutations (jackpot, consolidation, drawdown)
- Load-once / store-once for all multi-mutation pool functions
- Hard drain gate inside `_swapTicketSlot` itself — dual-layer protection beyond advanceGame flow control
- Single `_unfreezePool()` function is the only unfreeze path; never write `prizePoolFrozen = false` directly

### Critical Pitfalls

1. **Storage collision in Slot 1** — Add 3 new fields strictly after `purchaseStartDay` in declaration order; run `forge inspect DegenerusGameStorage storage-layout` and diff against the byte-offset header comment before touching any module. One wrong insertion shifts all subsequent bytes in all modules.

2. **Stale module artifact from incremental build** — Always `forge clean && forge build` after any storage layout change. A module compiled against the old layout silently reads wrong slot offsets; tickets land in one mapping key, processing reads from another, both succeed without error.

3. **`_tqReadKey`/`_tqWriteKey` inversion bug** — The two helpers are mirror images; the natural mistake is copy-pasting the wrong condition. Write the unit test first: for `ticketWriteSlot == 0`, assert `_tqWriteKey(5) == 5` and `_tqReadKey(5) == 5 | TICKET_SLOT_BIT`. Add invariant: `_tqWriteKey(level) != _tqReadKey(level)` always.

4. **Freeze branch missing in a purchase path** — After migrating to `prizePoolsPacked`, the old variable names become compile errors — use this as the completeness check. Then run an integration test that exercises every purchase path under active freeze and asserts pending accumulators grew while live pools did not.

5. **Unfreeze called at wrong point in `advanceGame`** — The `do { } while(false)` structure has multiple break exits; any break that bypasses `_unfreezePool` leaves freeze permanently active. Map every break path and confirm freeze state. `_unfreezePool` is idempotent — prefer calling it at ambiguous sites rather than missing it.

## Implications for Roadmap

Based on the dependency graph in FEATURES.md and the build order in ARCHITECTURE.md, the implementation must flow strictly from storage outward to modules. No reordering is safe.

### Phase 1: Storage Foundation
**Rationale:** Every subsequent change depends on the storage layout being correct and stable. The delegatecall architecture makes this the highest-leverage and highest-risk change — getting it wrong invalidates all downstream work. Must be complete and verified before any module is touched.
**Delivers:** Slot 1 additions (`ticketWriteSlot`, `ticketsFullyProcessed`, `prizePoolFrozen`); packed pool slots (`prizePoolsPacked`, `prizePoolPendingPacked`); bit-23 key encoding constants; all new helper functions (`_tqWriteKey`, `_tqReadKey`, `_getPrizePools`, `_setPrizePools`, `_getPendingPools`, `_setPendingPools`, `_swapTicketSlot`, `_swapAndFreeze`, `_unfreezePool`); updated `_queueTickets*` helpers to use write-key.
**Addresses:** Table-stakes features: write slot isolation foundation, packed prize pool storage, storage prerequisites for freeze flag.
**Avoids:** Storage collision (Pitfall 1), stale module artifacts (Pitfall 2), read/write key inversion (Pitfall 3, unit-tested here).

### Phase 2: Module Migration — Packed Pool Helpers
**Rationale:** Mechanical migration of all `nextPrizePool`/`futurePrizePool` accesses to `_getPrizePools`/`_setPrizePools` across 11 files. No behavior change — purely an API swap. Must happen before freeze branches are added (freeze branches depend on packed helpers existing). Removing the old variables as compile-time verification is the acceptance criterion.
**Delivers:** JackpotModule, EndgameModule, DecimatorModule, AdvanceModule internals, and `payDailyJackpot` / `consolidatePrizePools` all using load-once/store-once packed helpers. Zero occurrences of `nextPrizePool`/`futurePrizePool` outside comments.
**Uses:** `_getPrizePools`/`_setPrizePools` from Phase 1. `via_ir` optimizer for load-once/store-once pattern efficiency.
**Avoids:** uint128 truncation (Pitfall 4) — fuzz round-trip tests for each migrated function.

### Phase 3: Freeze/Unfreeze Coverage
**Rationale:** With packed helpers in place, add the freeze branch to all 9 purchase-path pool addition sites. This is the prerequisite for removing the `rngLockedFlag` reverts — the freeze must be in place before the lock is removed, otherwise there is a window where purchases are open and pools are unprotected.
**Delivers:** Freeze branch in `recordMint`, ETH receive fallback, lootbox pool split (MintModule), all whale bundle/lazy-pass splits (WhaleModule), degenerette bet split (DegeneretteModule). Pending accumulators populated correctly under freeze. Integration test covering all purchase paths under freeze.
**Implements:** Prize pool freeze state machine; pending accumulator atomic application pattern.
**Avoids:** Missing freeze branch in a purchase path (Pitfall 5); reentrancy around unfreeze (Pitfall 9).

### Phase 4: advanceGame Rewrite
**Rationale:** The most complex change — rewrites the daily state machine to incorporate mid-day path, drain gates, swap/freeze at RNG request, and unfreeze at correct exit points. All prior phases must be complete because this code calls `_swapAndFreeze`, `_unfreezePool`, and the read-key queue processing functions.
**Delivers:** Mid-day queue processing path, daily drain gate, `_swapAndFreeze` at RNG request, `_unfreezePool` at three designated points, `ticketsFullyProcessed` flag management. Revised `processTicketBatch` + `_processOneTicketEntry` using read-key (JackpotModule), `processFutureTicketBatch` using read-key (MintModule).
**Avoids:** Unfreeze at wrong point (Pitfall 6), `ticketsFullyProcessed` reset missing after mid-day swap (Pitfall 10), wrong level in hard gate check (Pitfall 7), constructor ticket slot mismatch (Pitfall 8).

### Phase 5: Lock Removal + Integration Validation
**Rationale:** Removing the two `rngLockedFlag` reverts from MintModule is the payoff — safe only after all other phases are complete and tested. This phase also covers the full integration test suite: purchase-during-RNG-lock, mid-day threshold trigger, jackpot-phase multi-day freeze persistence.
**Delivers:** Always-open purchases live; `rngLockedFlag` purchase reverts removed; full Foundry fuzz suite updated; gas snapshot confirming SSTORE reduction from packed pools.
**Avoids:** Premature lock removal before freeze coverage is complete.

### Phase Ordering Rationale

- Storage must precede modules because all modules compile the storage layout into their bytecode. Changing storage after touching modules requires a `forge clean` rebuild of everything.
- Packed pool migration precedes freeze branches because freeze branches call `_getPrizePools`/`_setPrizePools` — they cannot be written until those helpers exist.
- Freeze branches precede `advanceGame` rewrite because `advanceGame` is the function that removes the lock; the lock can only be removed safely when freeze protection is in place everywhere.
- Lock removal is last because it is both the simplest change (2 lines deleted) and the riskiest deployment — it is irreversible without a new deploy.

### Research Flags

Phases with well-documented patterns (no additional research needed — implementation plan is authoritative):
- **Phase 1 (Storage):** Slot layout and bit-packing patterns are fully specified in `PLAN-ALWAYS-OPEN-PURCHASES.md` and verified against `DegenerusGameStorage.sol`.
- **Phase 2 (Module Migration):** Mechanical — grep-driven, compile-verified, fuzz-tested.
- **Phase 3 (Freeze):** Freeze/accumulator pattern is standard DeFi; implementation sites are enumerated in the plan.

Phases that may benefit from deeper review during planning:
- **Phase 4 (advanceGame Rewrite):** The `do { } while(false)` state machine is the most complex change. The plan provides pseudocode but the actual implementation will require careful break-path analysis. Consider a dedicated review step mapping every break exit to its freeze-state expectation before writing code.
- **Phase 5 (Integration Validation):** The multi-day jackpot freeze persistence test requires simulating 5 sequential daily cycles with active purchases between each. This is test infrastructure work, not just a quick smoke test.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All patterns verified against actual contract source and `foundry.toml`. No new dependencies. Bit-23 key encoding confirmed against existing `dailyTicketBudgetsPacked` precedent in the same file. |
| Features | HIGH | Sourced directly from `PLAN-ALWAYS-OPEN-PURCHASES.md` (implementation-ready) and `DegenerusGameStorage.sol` (direct inspection). Feature dependency graph is arithmetic, not opinion. |
| Architecture | HIGH | Sourced from direct contract source inspection. Component list and change scope derived from grep counts (101 occurrences, 15 `rngLockedFlag` sites) — not estimated. |
| Pitfalls | HIGH | Storage collision and stale artifact pitfalls are established Solidity/delegatecall patterns. Key inversion and uint128 truncation are project-specific but fully specified. One MEDIUM note: Solidity 0.8 implicit narrowing behavior in local assignment is version-specific; verify with an actual compile test. |

**Overall confidence:** HIGH

### Gaps to Address

- **Multi-level drain gate coverage (Pitfall 7):** The plan's `_swapTicketSlot` checks only `_tqReadKey(purchaseLevel)`. Confirm during Phase 4 implementation whether multiple levels can coexist in the read slot simultaneously and whether a single-key gate is sufficient or requires iterating all active read keys.
- **`ticketCursor` reset after mid-day swap:** The plan specifies `ticketsFullyProcessed = false` resets the flag, but `ticketCursor` must also reset to 0. Confirm in Phase 4 that the cursor reset is explicitly in the swap function or the drain loop's re-entry path.
- **uint128 implicit narrowing in local assignment:** The PITFALLS research notes this is MEDIUM confidence for Solidity 0.8 version-specific behavior. Validate with a compile test during Phase 1 — use explicit `uint128` local declarations to force compiler errors on any `uint256` right-hand side.

## Sources

### Primary (HIGH confidence)
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/PLAN-ALWAYS-OPEN-PURCHASES.md` — implementation plan, pseudocode, invariants, enumerated call sites
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/storage/DegenerusGameStorage.sol` — storage layout, existing patterns, Slot 1 padding confirmation
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameAdvanceModule.sol` — current `advanceGame` flow, `rngLockedFlag` set/clear points
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameJackpotModule.sol` — `processTicketBatch`, pool mutation patterns
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameMintModule.sol` — purchase lock reverts, `processFutureTicketBatch`
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/DegenerusGame.sol` — `recordMint`, ETH receive, non-purchase `rngLockedFlag` gates
- `/home/zak/Dev/PurgeGame/degenerus-audit/foundry.toml` — `via_ir = true`, `optimizer_runs = 2`, `solc_version = "0.8.34"`
- `/home/zak/Dev/PurgeGame/degenerus-audit/node_modules/@openzeppelin/contracts/package.json` — OZ 5.4.0 confirmed

### Secondary (MEDIUM confidence)
- Training-data knowledge of Chainlink VRF subscription management, Synthetix/Compound accumulator patterns, and delegatecall storage alignment constraints — patterns are well-established but not verified against current docs

---
*Research completed: 2026-03-11*
*Ready for roadmap: yes*
