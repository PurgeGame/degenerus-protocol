# Milestones

## v1.0 Always-Open Purchases (Shipped: 2026-03-11)

**Phases completed:** 5 phases, 8 plans, 0 tasks

**Key accomplishments:**
- Double-buffered ticket queue with bit-23 key encoding — purchases never block during RNG processing
- Packed prize pools (uint128+uint128) saving 1 SSTORE per purchase across all 7 pool addition sites
- Prize pool freeze/unfreeze with pending accumulators that persist across all 5 jackpot days
- advanceGame rewritten with mid-day swap path (440 threshold) and pre-RNG drain gate
- Removed 6 rngLockedFlag purchase-path guards from MintModule, LootboxModule, DegeneretteModule, AdvanceModule
- 66 milestone-specific tests (StorageFoundation, QueueDoubleBuffer, PrizePoolFreeze, AdvanceGameRewrite, LockRemoval)

**Stats:** 16 files changed, +1,921 / -183 lines, ~2 hours execution
**Git range:** dca6cb33..f4a6596e

---

