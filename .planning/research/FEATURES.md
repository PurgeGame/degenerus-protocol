# Feature Research

**Domain:** On-chain game infrastructure — always-open purchase system with double-buffered queues and prize pool freeze mechanics
**Researched:** 2026-03-11
**Confidence:** HIGH (plan is implementation-ready; findings derive from the detailed PLAN-ALWAYS-OPEN-PURCHASES.md and direct contract source inspection)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features the game must have for always-open purchases to be credible. Missing any of these means the core value proposition ("buy at any time, never reverted") is broken or unsafe.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Remove `rngLockedFlag` purchase reverts | Core value prop: purchases must never revert during daily processing | LOW | Two lines deleted from MintModule — trivial mechanical change but depends on every other feature being in place first |
| Write slot isolation for new purchases | If new buys still land in the queue being processed, processing is non-deterministic | MEDIUM | Bit-23 key encoding reuses existing mappings; no new mapping declarations; all `_queueTickets*` functions updated |
| Read slot drain gate before any swap | Prevents data loss — swapping while read slot has entries would silently orphan tickets | LOW | Enforced inside `_swapTicketSlot()` with `ReadSlotNotDrained` revert; two-layer protection |
| Prize pool freeze during daily RNG | Jackpot payout amounts must not be inflated by concurrent purchases mid-processing | MEDIUM | Freeze only at daily RNG request; pending accumulators redirect purchase revenue; unfreeze at defined checkpoints only |
| Pending accumulator atomic application | Pending revenue must be applied before freeze clears, with no gap where it could be lost | LOW | `_unfreezePool()` is the single unfreeze point; adds pending to live pools in same call; not split across transactions |
| `ticketsFullyProcessed` gate before jackpots | Jackpots must not execute until all tickets for the day are assigned; prevents reward miscounts | LOW | Boolean flag in Slot 1 padding; set true after read slot drains; checked before any jackpot/payout logic |

### Differentiators (Competitive Advantage)

Features that go beyond "not broken" to deliver genuine gas and UX quality improvements.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Mid-day queue swap path | Prevents queue backlog from accumulating across days; keeper can drain large queues early without triggering a full daily cycle | MEDIUM | Triggers when write queue >= 440 entries OR jackpot phase active; no freeze on mid-day swap; requires `ticketsFullyProcessed` check to avoid re-processing |
| Packed prize pools (`uint128+uint128` in one slot) | Saves 1 SSTORE per purchase across all purchase paths — lootbox, whale bundle, degenerette, ticket — adds up to significant savings at volume | MEDIUM | Max uint128 ~3.4e20 ETH exceeds total ETH supply; functions that touch both pools collapse from 3+ SSTOREs to 1 SLOAD + 1 SSTORE; `consolidatePrizePools` and `payDailyJackpot` benefit most |
| Packed pending accumulators (same `uint128+uint128` pattern) | Freeze branch adds zero marginal SSTORE cost vs non-frozen path | LOW | Single `prizePoolPendingPacked` slot; zeroed with single SSTORE at unfreeze |
| Freeze persists across all 5 jackpot draw days | All jackpot payouts use the pre-freeze pool value, not inflated by intra-phase purchases; predictable prize sizing for players | MEDIUM | Accumulators persist (not reset) between jackpot days; each day's swap does not reset pending; only `_endPhase()` unfreezes |
| Bit-23 key encoding for double buffer | Zero new storage slots, zero mapping type changes, zero storage layout migration risk | LOW | Max real level 2^23 - 1 = 8,388,607; game would take centuries to reach; encoding is invisible to callers |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Freeze prize pools on mid-day swap | "Consistency" — some might argue any queue swap should freeze pools | Mid-day processing only handles ticket assignment, never jackpot payouts or threshold checks; freezing unnecessarily blocks purchase revenue from accumulating in live pools and delays `lastPurchaseDay` threshold crossing | Only freeze at daily RNG request where jackpot payouts actually occur |
| Resetting pending accumulators between jackpot days | "Clean slate" each jackpot day | Revenue accumulated from purchases during jackpot phase days 1-4 would be silently discarded; players lose pool contributions | Persist accumulators for the full jackpot phase; apply once at `_endPhase()` |
| Separate new mappings for the second queue slot | "Clearer code" | New mapping declaration changes storage slot numbers for every subsequent state variable; requires storage migration or proxy upgrade | Bit-23 encoding in the key reuses existing `ticketQueue` and `ticketsOwedPacked` mappings with zero slot impact |
| Multiple unfreeze call sites (inline in each module) | "Simplicity" per module | Split unfreeze logic risks partial application — pending added without clearing, or flag cleared without adding pending | Single `_unfreezePool()` function is the only unfreeze path; enforced by code structure |
| Allowing RNG request before read slot is drained | "Throughput" — one daily cycle regardless | Would cause ticket orphaning: swapped-away entries in the old read slot are never processed; players' tickets silently lost | Hard gate in `_swapTicketSlot()` reverts if read slot non-empty; advanceGame drains before reaching swap |

---

## Feature Dependencies

```
[Remove rngLockedFlag reverts]
    └──requires──> [Write slot isolation]
                       └──requires──> [Bit-23 key encoding]
                                          └──requires──> [Slot 1 storage: ticketWriteSlot uint8]

[Mid-day queue swap]
    └──requires──> [Write slot isolation]
    └──requires──> [Read slot drain gate]
    └──requires──> [ticketsFullyProcessed flag]

[Prize pool freeze]
    └──requires──> [Packed prize pools (prizePoolsPacked)]
    └──requires──> [Packed pending accumulators (prizePoolPendingPacked)]
    └──requires──> [Slot 1 storage: prizePoolFrozen bool]

[Remove rngLockedFlag reverts]
    └──requires──> [Prize pool freeze]  (freeze must exist before lock is removed, otherwise
                                         jackpot payouts can be inflated by concurrent purchases)

[Jackpot phase freeze persistence]
    └──requires──> [Prize pool freeze]
    └──requires──> [ticketsFullyProcessed gate before jackpots]

[Packed prize pools]
    └──enhances──> [Prize pool freeze]  (both pending and live pools share same packing pattern;
                                         freeze branch costs zero marginal SSTOREs)

[Mid-day queue swap] ──conflicts──> [Prize pool freeze on mid-day]
    (mid-day swap must NOT trigger freeze; freeze only at daily RNG request)
```

### Dependency Notes

- **Remove `rngLockedFlag` reverts requires write slot isolation:** The lock existed precisely because processing and writing shared the same queue. Without isolation, removing the lock would corrupt queue state. Write slot isolation must land first (or simultaneously as an atomic changeset).
- **Write slot isolation requires Slot 1 additions:** `ticketWriteSlot` (uint8) and `ticketsFullyProcessed` (bool) must be added to the 14-byte padding in Slot 1 before any queue logic changes.
- **Prize pool freeze requires packed storage:** The freeze branch pattern (load once, branch to pending or live, store once) only achieves its gas efficiency with packed helpers. Implementing freeze on top of separate `nextPrizePool`/`futurePrizePool` slots would be correct but wasteful; doing packed storage and freeze together is the right unit of work.
- **Jackpot phase freeze persistence requires correct unfreeze placement:** If `_unfreezePool()` is called between jackpot days (e.g., at each `_unlockRng`), the day-1 payout uses frozen pools but day-2 onward uses inflated ones. The plan is explicit: unfreeze only at `_endPhase()` and at purchase-phase daily completion — not between jackpot days.
- **`ticketsFullyProcessed` gate is load-bearing for the daily path:** The mid-day path sets this flag when the read slot drains mid-day; the daily path checks it before attempting jackpot logic. Without this flag, a mid-day drain could leave the daily path confused about queue state.

---

## MVP Definition

This is an infrastructure milestone, not a product launch. "MVP" here means the minimum coherent set that delivers always-open purchases without introducing new invariant violations.

### Launch With (v1 — all required, not separable in production)

- [x] Slot 1 storage additions: `ticketWriteSlot`, `ticketsFullyProcessed`, `prizePoolFrozen` — foundation for everything else
- [x] Packed prize pool storage (`prizePoolsPacked`, `prizePoolPendingPacked`) with `_getPrizePools`/`_setPrizePools`/`_getPendingPools`/`_setPendingPools` helpers — prerequisite for freeze
- [x] Bit-23 key encoding constants and `_tqWriteKey`/`_tqReadKey` helpers — prerequisite for write isolation
- [x] Update all `_queueTickets*` to use write key — buy-side isolation
- [x] Update all processing functions to use read key — processing-side isolation
- [x] `_swapTicketSlot()` with hard drain gate (`ReadSlotNotDrained` revert) — invariant enforcement
- [x] `_swapAndFreeze()` — daily RNG path entry point
- [x] `_unfreezePool()` — single unfreeze point
- [x] Freeze branch in all purchase-path pool additions (recordMint, lootbox, whale bundle, degenerette, ETH fallback)
- [x] Revised `advanceGame` flow: mid-day path, daily gate, `_swapAndFreeze` at RNG request, `_unfreezePool` at unlock points
- [x] Remove `rngLockedFlag` reverts from MintModule — the payoff; only safe once all the above is in place

### Add After Validation (v1.x)

- [ ] Mid-day processing path — valuable for queue backlog management but not required for correctness; the system is correct without it (queues just drain at daily cadence); add once daily path is verified stable
- [ ] Bounty tuning for mid-day advanceGame calls — depends on mid-day path existing

### Future Consideration (v2+)

- [ ] Full gas optimization pass beyond packed pools — separate effort explicitly called out as out of scope
- [ ] Frontend purchase UX updates to reflect always-open state — contract-level only in this milestone
- [ ] DGNRS token changes — already soulbound, explicitly out of scope

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Remove `rngLockedFlag` reverts | HIGH — direct UX fix | LOW (2 lines deleted) | P1 — but must be last step |
| Write slot isolation (key encoding + queue updates) | HIGH — prerequisite for safe lock removal | MEDIUM | P1 |
| Prize pool freeze + pending accumulators | HIGH — jackpot integrity | MEDIUM | P1 |
| Slot 1 storage additions | HIGH — foundational | LOW | P1 |
| Packed prize pool storage | MEDIUM — gas savings per purchase | MEDIUM | P1 (paired with freeze) |
| Revised `advanceGame` flow | HIGH — orchestrates all the above | HIGH (most logic lives here) | P1 |
| `ticketsFullyProcessed` gate | HIGH — jackpot safety invariant | LOW | P1 |
| `_swapTicketSlot()` hard drain gate | HIGH — orphan prevention | LOW | P1 |
| Mid-day queue swap path | MEDIUM — throughput, not correctness | MEDIUM | P2 |
| Foundry test suite updates | HIGH — confidence gate | MEDIUM | P1 (parallel with implementation) |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## On-Chain Pattern Context

These observations are from training-data knowledge of how similar systems handle the same problems. Confidence is MEDIUM (training data, not verified against current docs).

**Double-buffer queues on-chain.** The core pattern (write to inactive slot, process from active slot, swap atomically) is the same used in Chainlink VRF subscription management and Uniswap V3's fee accumulator design — a pattern where reads and writes must not interfere. The bit-23 key encoding is a Degenerus-specific optimization over the more common approach of two separate mappings; it avoids storage slot renumbering at the cost of a slightly non-obvious key derivation. This is the correct tradeoff for an existing deployed storage layout.

**Prize pool freeze / snapshot mechanics.** The pattern of "freeze the canonical value, accumulate new contributions separately, apply atomically at a defined checkpoint" is standard in DeFi staking (e.g., Synthetix rewards snapshots, Compound's interest accrual). The critical invariant is always the same: the checkpoint must be atomic and the pending accumulator must be zeroed in the same call that applies it. `_unfreezePool()` satisfies this. The risk in all such systems is split application (partial flush), which the single-function approach prevents.

**Mid-day batch processing.** Chainlink Automation (formerly Keepers) patterns commonly use a threshold-triggered mid-cycle flush rather than a time-triggered one — exactly what the 440-entry threshold does. The choice to not freeze on mid-day is correct: batch processing of ticket assignment does not alter payout amounts, so the pool integrity invariant is not at risk.

**Delegatecall module storage safety.** The plan's constraint of fitting new fields into existing Slot 1 padding is not cosmetic — it is a hard requirement of the delegatecall architecture. Every module that inherits `DegenerusGameStorage` must see identical slot layout. Adding new slots at the end of the packed region is safe; inserting fields mid-layout would shift all subsequent slots in every module simultaneously. The plan's approach (3 bytes into 14-byte Slot 1 padding) is the lowest-risk storage change possible.

---

## Sources

- `/audit/PLAN-ALWAYS-OPEN-PURCHASES.md` — primary source; implementation-ready plan with full storage, code, and invariant specifications (HIGH confidence)
- `/contracts/storage/DegenerusGameStorage.sol` — direct source inspection confirming Slot 1 has 14-byte padding at bytes [18:32] and confirming existing `rngLockedFlag` location (HIGH confidence)
- `.planning/PROJECT.md` — milestone scope and out-of-scope boundaries (HIGH confidence)
- Training-data knowledge of Chainlink VRF, Synthetix/Compound accumulator patterns, and delegatecall storage constraints (MEDIUM confidence — patterns are well-established but not verified against current docs)

---
*Feature research for: Degenerus Protocol — always-open purchase infrastructure*
*Researched: 2026-03-11*
