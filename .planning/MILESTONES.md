# Milestones

## v1.1 Economic Flow Analysis (Shipped: 2026-03-12)

**Phases completed:** 6 phases, 15 plans, 0 tasks

**Key accomplishments:**
- Mapped all 9 ETH purchase paths with exact cost formulas and 14-row pool split table across all purchase types and conditions
- Documented complete jackpot mechanics — purchase-phase daily drip, 5-day draw sequence with trait buckets, BAF/Decimator transition jackpots with worked examples and simulation pseudocode
- Modeled BURNIE token economy — coinflip odds with ~1.575% house edge derivation, all earning/burning paths, vault reserve invariant
- Documented full price curve across all level ranges, activity score system, death clock escalation, and terminal distribution formulas
- Covered all reward modifiers — DGNRS 6-pool tokenomics, deity boon probability tables (3 scenarios), affiliate tiers, stETH yield, quest slot mechanics
- Consolidated ~200+ protocol constants into master parameter reference with values, units, and contract locations

**Stats:** 13 reference documents, 8,511 lines, 143 commits over 2 days
**Output:** `audit/v1.1-*.md` (13 files)
**Audit:** 44/44 requirements satisfied, 51/51 must-have truths verified (TECH DEBT status — 3 low-severity readability items)

---

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

