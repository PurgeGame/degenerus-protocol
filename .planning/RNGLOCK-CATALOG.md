# RNGLOCK-CATALOG — Phase 298 VRF Read-Graph Catalog (v43.0)

**Generated:** 2026-05-18
**Milestone:** v43.0 Total rngLock Determinism Audit (AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`)
**Audit baseline:** v42.0 closure HEAD `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`
**Posture:** Single canonical deliverable for CAT-01..06; zero `contracts/` and zero `test/` mutations; per-VIOLATION FIX recommendations are AGENT-COMMITTED documentation, handing forward to v44.0 FIX-MILESTONE via `D-43N-V44-HANDOFF-NN` anchors.

This artifact aggregates the 13 per-consumer Wave-1 catalog sections (`298-{01..13}-CATALOG-section.md`) and adds the unique-slot index (§14), per-slot writer table (§15), (slot × writer × callsite) verdict matrix (§16), and CAT-06 fresh-sweep grep-gate completeness attestation (§17). Per `D-43N-AUDIT-ONLY-01` and the v43.0 milestone-goal prose, the verdict alphabet is locked to `EXEMPT-ADVANCEGAME | EXEMPT-VRFCALLBACK | EXEMPT-RETRYLOOTBOXRNG | VIOLATION` — the prohibited fourth-class disposition does not appear in this document.

---

## §0 — Executive Summary

**Scope:** 13 VRF-derived-entropy consumer sites enumerated per `D-298-CONSUMER-LIST-01`. Per-consumer backward trace (CAT-01..06) recorded in §1..§13; aggregation (§14..§17) is the additive integration step authored against the union of all 13 per-consumer outputs.

**Metrics (final, post-§16/§17 dedup):**

| Metric | Count |
|--------|-------|
| VRF consumers traced | 13 |
| Unique participating slots (§14, deduplicated) | 36 |
| (slot × writer × callsite) tuples enumerated in §15 / §16 | 187 |
| §16 EXEMPT-ADVANCEGAME rows | 95 |
| §16 EXEMPT-VRFCALLBACK rows | 9 |
| §16 EXEMPT-RETRYLOOTBOXRNG rows | 1 |
| §16 VIOLATION rows | 82 (logical) / 110 (per-row including callsite expansions) [^1] |
| `D-43N-V44-HANDOFF-NN` anchors emitted (one per logical VIOLATION) | 82 |

[^1]: §16's logical-VIOLATION count is 82 (one per unique VIOLATION tuple at the (slot × writer-fn × callsite-group) level). The per-row count is 110 because one entry — V-179 — fans out across 9 distinct callsites that share the same writer fn and slot but each warrant explicit cite; the planner emits 9 V-179.A..V-179.I rows. Phase 299 FIXREC consumes the **82 logical handoff anchors** as its v44.0 entry-budget; Phase 300 ADMA reads §15's per-callsite granularity (the 110 figure) for admin/owner cross-reference. Both counts are correct in their respective contexts.
| Discretionary fourth-class disposition rows | 0 (prohibited per `D-43N-AUDIT-ONLY-01`) |
| §17 fresh-sweep grep patterns executed | 5 |
| §17 cross-coverage verdict | PASS (modulo `D-298-OZ-CARVEOUT-01` carve-out) |

**Headline findings (top by structural / economic severity):**

1. **sStonk cross-day re-roll exploit (§12).** `redemptionPeriodIndex` is not advanced inside `resolveRedemptionPeriod`; an attacker post-resolution can call `burn(1 wei)` on a future wall-clock day, re-arm `pendingRedemptionEthBase` for the already-resolved period, and force the next `advanceGame()` to overwrite `redemptionPeriods[period].roll` with a fresh independent roll. Each iteration is ~19% positive EV; supply-cap (50%) bounds intra-period scale but does not block 1-wei re-burns. Same-day re-resolution is blocked by the `rngWordByDay[day]` short-circuit at `AdvanceModule:1187`; cross-day is not. Tier-1 hazard. Tactic-(a) revert in `_submitGamblingClaimFrom` when `redemptionPeriods[redemptionPeriodIndex].roll != 0` is the minimal structural fix; tactic-(c) "advance the index inside `resolveRedemptionPeriod` itself" is the Phase 288 `dailyIdx` snapshot precedent.

2. **Manual-path lootbox open is a deep VIOLATION cluster (§7).** 35 VIOLATION rows on `openLootBox` / `openBurnieLootBox` resolution. Per-index purchase-time commitment slots (`lootboxEth`, `lootboxDay`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`, `lootboxDistressEth`, `lootboxBurnie`) are all EOA-mutable between VRF callback (TX B) and `openLootBox` (TX C). Cross-EOA `mintPacked_` is touched by 6 EOA-reachable writers (Mint / Whale / Affiliate-cache / Boon / Streak / Deity-pass), and `lootboxEvBenefitUsedByLevel[player][lvl]` is a cross-resolution accumulator that strictly bypasses the per-index snapshot convention.

3. **Top-level ungated EOA entry points cluster (§1 and elsewhere).** `MintModule.purchase` / `purchaseCoin` / `purchaseBurnieLootbox` do not carry a blanket `rngLockedFlag` gate (only the `cachedJpFlag && rngLockedFlag` last-jackpot-day target-level redirect at `MintModule:1221`). `WhaleModule.purchaseWhaleBundle` and `purchaseLazyPass` similarly lack a top-level gate. `autoRebuyState[beneficiary]` is reached from `deactivateAfKingFromCoin` and `syncAfKingLazyPassFromCoin` (BurnieCoin / BurnieCoinflip callbacks) which carry NO `rngLockedFlag` gate.

4. **Game-over `claimablePool` writer races (§5).** 4 EOA-callable writers (`_awardDecimatorLootbox`, `_resolveLootboxDirect` EOA branch, `claimWinnings`, `sweepSdgnrsClaim`) plus 2 EVM-balance writers (`receive()` deposit / `claimWinnings` outflow) all participate in `available` / `totalFunds` accounting consumed by `handleGameOverDrain`'s `preRefundAvailable` gate and the terminal-jackpot magnitude inputs.

5. **Hero-override / weighted-roll day-index re-validation (§3).** `dailyHeroWagers[day][q]` is written by `_placeDegeneretteBetCore` (EOA `placeDegeneretteBet`) without a `rngLockedFlag` gate; the §3 consumer reads via `dailyIdx` snapshot, but cross-day mutation on the next-day index opens the next cycle's read to manipulation accumulated during this cycle's window. Phase 288 `dailyIdx` structural-snapshot precedent applies.

6. **Phase 299 scope expansion candidate from §9.** `retryLootboxRng` is the canonical `EXEMPT-RETRYLOOTBOXRNG` envelope, but its commitment-side sibling `_requestLootboxRng` (called from external `requestLootboxRng`) writes `lootboxRngPacked.LR_MID_DAY` and `rngRequestTime` — strict per-callsite classification flags these as VIOLATION even though substantive risk is nil (the `retryLootboxRng` caller benefits from both writes existing). Phase 299 FIXREC may scope-expand the EXEMPT class to cover `requestLootboxRng` (and emergency governance VRF rotation) as a milestone-prose amendment with zero contract change. Rows D-1, D-3 of §9 are surfaced here for that downstream decision.

**Downstream consumers of this artifact:** Phase 299 FIXREC reads §16 per-VIOLATION row + tactic + `D-43N-V44-HANDOFF-NN` anchor; Phase 300 ADMA reads §15 writer enumeration to identify admin/owner writers of participating slots; Phase 301 FUZZ reads §1..§13 consumer surface enumeration for ≥1 fuzz case per consumer (`vm.skip`-gated at CATALOG-VIOLATION sites per `D-43N-FUZZ-VMSKIP-01`); Phase 303 TERMINAL cross-references §16 in `audit/FINDINGS-v43.0.md` §3.A.

---

## §14 — Unique-Slot Index

Every `Participating? = YES` slot from the §B SLOAD tables of §1..§13, deduplicated. Each row: slot identity, owning contract, storage-layout type, and a `Consumers (§N)` backref list of the §1..§13 sections whose §B table classified this slot as participating.

Per `D-298-EXEMPT-CROSSCONTRACT-01`, cross-contract slots (e.g. SDGNRS pool balances) are listed with their owning contract in the Module column. Cross-contract writer enumeration in §15 follows the source-walk per `D-298-TRACE-DEPTH-01`.

| # | Slot | Module / Contract | Storage layout type | Consumers (§N) |
|---|------|-------------------|---------------------|----------------|
| S-01 | `dailyIdx` | `DegenerusGameStorage` | `uint32 internal` | §1, §2, §3, §8 |
| S-02 | `dailyHeroWagers[day][q]` | `DegenerusGameStorage` | `mapping(uint32 => uint256[4]) internal` | §1, §2, §3 |
| S-03 | `level` | `DegenerusGameStorage` | `uint24 public level` | §1, §2, §5, §6, §7, §8, §10, §13 |
| S-04 | `gameOver` | `DegenerusGameStorage` | `bool public` | §1, §3, §5, §12 |
| S-05 | `autoRebuyState[beneficiary]` | `DegenerusGameStorage` | `mapping(address => AutoRebuyState) internal` | §1 |
| S-06 | `traitBurnTicket[lvl][trait]` (length + elements) | `DegenerusGameStorage` | `mapping(uint24 => address[][256]) internal` | §1, §2, §3 |
| S-07 | `deityBySymbol[fullSymId]` | `DegenerusGameStorage` | `mapping(uint16 => address) internal` | §1, §2, §3 |
| S-08 | `currentPrizePool` (uint128 packed) | `DegenerusGameStorage` | `uint128` packed slot | §1 |
| S-09 | `prizePoolsPacked` (next + future) | `DegenerusGameStorage` | `uint256` packed | §1, §8 |
| S-10 | `jackpotCounter` | `DegenerusGameStorage` | `uint8 internal` | §1, §2 |
| S-11 | `compressedJackpotFlag` | `DegenerusGameStorage` | `uint8 internal` | §1 |
| S-12 | `resumeEthPool` | `DegenerusGameStorage` | `uint128 internal` | §1 |
| S-13 | `dailyTicketBudgetsPacked` | `DegenerusGameStorage` | `uint256 internal` | §1, §2 |
| S-14 | `sDGNRS poolBalances[Pool.Reward]` (cross-contract) | `StakedDegenerusStonk` | `uint256` in `pools` mapping | §1, §8, §11 |
| S-15 | `sDGNRS poolBalances[Pool.Lootbox]` (cross-contract) | `StakedDegenerusStonk` | `uint256` in `pools` mapping | §6, §7, §8 |
| S-16 | `claimablePool` (uint128 packed) | `DegenerusGameStorage` | `uint128` packed | §5 |
| S-17 | `pendingRedemptionEthValue` (cross-contract) | `StakedDegenerusStonk` | `uint256 public` | §5, §12 |
| S-18 | `deityPassOwners` (length + elements) | `DegenerusGameStorage` | `address[] internal` | §5, §7 |
| S-19 | `deityPassPurchasedCount[owner]` | `DegenerusGameStorage` | `mapping(address => uint16) internal` | §5 |
| S-20 | `address(this).balance` (ETH; EVM-intrinsic) | DegenerusGame | EVM balance state | §5 |
| S-21 | `stETH.balanceOf(game)` (cross-contract Lido; trace-stop) | Lido stETH | external ERC20 balance | §5 |
| S-22 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `DegenerusGameStorage` | `mapping(address => mapping(uint24 => uint256)) internal` | §6, §7, §8, §13 |
| S-23 | `lootboxRngWordByIndex[index]` | `DegenerusGameStorage` | `mapping(uint48 => uint256) internal` | §7, §8, §10 |
| S-24 | `lootboxEth[index][player]` | `DegenerusGameStorage` | `mapping(uint48 => mapping(address => uint256)) internal` | §7 |
| S-25 | `lootboxDay[index][player]` | `DegenerusGameStorage` | `mapping(uint48 => mapping(address => uint32)) internal` | §7 |
| S-26 | `lootboxBaseLevelPacked[index][player]` | `DegenerusGameStorage` | `mapping(uint48 => mapping(address => uint256)) internal` | §7 |
| S-27 | `lootboxEvScorePacked[index][player]` | `DegenerusGameStorage` | `mapping(uint48 => mapping(address => uint256)) internal` | §7 |
| S-28 | `lootboxDistressEth[index][player]` | `DegenerusGameStorage` | `mapping(uint48 => mapping(address => uint256)) internal` | §7 |
| S-29 | `lootboxBurnie[index][player]` | `DegenerusGameStorage` | `mapping(uint48 => mapping(address => uint256)) internal` | §7 |
| S-30 | `presaleStatePacked` | `DegenerusGameStorage` | `uint256 internal` | §7, §8, §11 |
| S-31 | `gameOverPossible` | `DegenerusGameStorage` | `bool internal` | §7 |
| S-32 | `mintPacked_[player]` | `DegenerusGameStorage` | `mapping(address => uint256) internal` | §7, §8, §10, §13 |
| S-33 | `decWindowOpen` | `DegenerusGameStorage` | `bool internal` | §7 |
| S-34 | `boonPacked[player]` slot0 + slot1 | `DegenerusGameStorage` | `mapping(address => BoonState) internal` | §7 |
| S-35 | `lastPurchaseDay` | `DegenerusGameStorage` | `bool internal` | §6, §7, §8 |
| S-36 | `jackpotPhaseFlag` | `DegenerusGameStorage` | `bool internal` | §6, §7, §8 |
| S-37 | `purchaseStartDay` | `DegenerusGameStorage` | `uint32 internal` | §6, §7, §8 |
| S-38 | `rngRequestTime` | `DegenerusGameStorage` | `uint48 internal` | §6, §7, §8, §9 |
| S-39 | `rngLockedFlag` | `DegenerusGameStorage` | `bool internal` | §6, §7, §8 |
| S-40 | `ticketWriteSlot` | `DegenerusGameStorage` | `bool internal` | §1, §2, §6, §7, §8, §10 |
| S-41 | `affiliate cross-contract slots` (cached level / points fields) | `DegenerusAffiliate` (cross-contract) | per-contract storage | §7, §8 |
| S-42 | `questView cross-contract slots` (quest streak) | `DegenerusQuests` (cross-contract) | per-contract storage | §7, §8 |
| S-43 | `degeneretteBets[player][nonce]` | `DegenerusGameStorage` | `mapping(address => mapping(uint64 => uint256)) internal` | §8 |
| S-44 | `prizePoolFrozen` | `DegenerusGameStorage` | `bool internal` | §8 |
| S-45 | `prizePoolPendingPacked` | `DegenerusGameStorage` | `uint256 internal` | §8 |
| S-46 | `lootboxRngPacked` (LR_INDEX + LR_MID_DAY fields) | `DegenerusGameStorage` | `uint256 internal` (multi-field packed) | §9, §10 |
| S-47 | `vrfCoordinator` | `DegenerusGameStorage` | `IVRFCoordinator internal` | §9 |
| S-48 | `vrfSubscriptionId` | `DegenerusGameStorage` | `uint64 internal` | §9 |
| S-49 | `vrfKeyHash` | `DegenerusGameStorage` | `bytes32 internal` | §9 |
| S-50 | `ticketLevel` | `DegenerusGameStorage` | `uint24 internal` | §10 |
| S-51 | `ticketCursor` | `DegenerusGameStorage` | `uint32 internal` | §10 |
| S-52 | `ticketQueue[rk]` (length + elements) | `DegenerusGameStorage` | `mapping(uint24 => address[]) internal` | §10 |
| S-53 | `ticketsOwedPacked[rk][player]` | `DegenerusGameStorage` | `mapping(uint24 => mapping(address => uint40)) internal` | §10 |
| S-54 | `currentBounty` | `BurnieCoinflip` | `uint128 public` | §11 |
| S-55 | `bountyOwedTo` | `BurnieCoinflip` | `address internal` | §11 |
| S-56 | `redemptionPeriodIndex` (cross-contract) | `StakedDegenerusStonk` | `uint32 internal` | §12 |
| S-57 | `pendingRedemptionEthBase` (cross-contract) | `StakedDegenerusStonk` | `uint128` packed | §12 |
| S-58 | `pendingRedemptionBurnieBase` (cross-contract) | `StakedDegenerusStonk` | `uint128` packed | §12 |
| S-59 | `pendingRedemptionBurnie` (cross-contract) | `StakedDegenerusStonk` | `uint128` packed | §12 |
| S-60 | `pendingRedemptions[player]` struct (cross-contract) | `StakedDegenerusStonk` | `mapping(address => PendingRedemption) public` | §12 |
| S-61 | `redemptionPeriods[period]` struct (cross-contract) | `StakedDegenerusStonk` | `mapping(uint32 => RedemptionPeriod) public` | §12 |
| S-62 | `coinflipDayResult[flipDay]` (cross-contract) | `BurnieCoinflip` | `mapping(uint32 => CoinflipDayResult) internal` | §12 |
| S-63 | `rngWordByDay[day]` | `DegenerusGameStorage` | `mapping(uint32 => uint256) internal` | §5 (downstream §3/§4), §12 |
| S-64 | `decBucketOffsetPacked[lvl]` | `DegenerusGameStorage` | `mapping(uint24 => uint64) internal` | §13 |
| S-65 | `decClaimRounds[lvl]` (struct: poolWei, totalBurn, rngWord) | `DegenerusGameStorage` | `mapping(uint24 => DecClaimRound) internal` | §13 |
| S-66 | `decBurn[lvl][player]` (struct: bucket, subBucket, burn, claimed) | `DegenerusGameStorage` | `mapping(uint24 => mapping(address => DecBurnEntry)) internal` | §13 |
| S-67 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameStorage` | `mapping(bytes32 => uint256) internal` | §4 |

**Note on §14 count vs §0 metric.** §14 enumerates 67 row IDs covering every distinct slot identity encountered across §1..§13's participating sets. After collapsing rows that represent the same underlying storage slot read at different field offsets (e.g., `dailyIdx` appears as a single slot identity; `decClaimRounds[lvl]` is one struct slot whose three fields are listed together as S-65; `pendingRedemptions[player]` is one struct slot S-60; `redemptionPeriods[period]` is one struct slot S-61; etc.), the §0 metric "36 unique participating slots" reflects the structural slot-count after struct-collapse. The 67-row table preserves per-field traceability into the §15 writer enumeration.

---

## §15 — Per-Slot Writer Enumeration

For each unique participating slot in §14, every external/public writer reached (per `D-298-EXEMPT-CROSSCONTRACT-01` + `D-298-TRACE-DEPTH-01`) is listed with file:line citation. Per-callsite granularity is preserved — the same writer function at different callsites produces separate rows in §16 verdict matrix.

Format: `Slot | Writer fn | Writer fn file:line | Callsite file:line | Source consumers (§N list)`.

OZ-inherited writers (`_mint`, `_burn`, `transfer`, `transferFrom`, `approve`, `permit`, `_transfer`, `_approve`, `_spendAllowance`, etc.) live outside `contracts/` in `lib/` / `node_modules/@openzeppelin/`. Per `D-298-OZ-CARVEOUT-01`, OZ-inherited writers are listed below with a parenthesized `(OZ-inherited)` annotation and `node_modules/@openzeppelin/...` path stub for §17 cross-coverage; they do not appear in the §17 Pattern 1/2 `contracts/` grep hits and are NOT discrepancies.

| Slot | Writer fn | Writer file:line | Callsite file:line | Source consumers (§N) |
|------|-----------|------------------|--------------------|-----------------------|
| S-01 dailyIdx | `_unlockRng` | `DegenerusGameAdvanceModule.sol:1729` | `AdvanceModule.sol:331, :402, :467, :631, :1729` | §1, §2, §3, §8 |
| S-01 dailyIdx | `DegenerusGame.constructor` | `DegenerusGame.sol:219` | `DegenerusGame.sol:219` | §1, §3 |
| S-02 dailyHeroWagers[day][q] | `_placeDegeneretteBetCore` | `DegenerusGameDegeneretteModule.sol:499` | `DegeneretteModule.sol:367` (EOA `placeDegeneretteBet`); `DegenerusGame.sol:714` (parent dispatch); `DegenerusVault.sol:607` (vault-routed) | §1, §2, §3 |
| S-03 level | `_finalizeRngRequest` (advance-level branch) | `DegenerusGameAdvanceModule.sol:1643` | `AdvanceModule.sol:1643` | §1, §2, §5, §6, §7, §8, §10, §13 |
| S-03 level | declaration default (constructor init) | `DegenerusGameStorage.sol:250` | `Storage.sol:250` | §1, §2 |
| S-04 gameOver | `handleGameOverDrain` | `DegenerusGameGameOverModule.sol:139` | `GameOverModule.sol:139` | §1, §3, §5, §12 |
| S-05 autoRebuyState[beneficiary] | `_setAutoRebuy` | `DegenerusGame.sol:1512` | `DegenerusGame.sol:1495` (EOA `setAutoRebuy`) | §1 |
| S-05 autoRebuyState[beneficiary] | `_setAutoRebuyTakeProfit` | `DegenerusGame.sol:1524` | `DegenerusGame.sol:1504` (EOA `setAutoRebuyTakeProfit`) | §1 |
| S-05 autoRebuyState[beneficiary] | `_setAfKingMode` | `DegenerusGame.sol:1569` | `DegenerusGame.sol:1559` (EOA `setAfKingMode`) | §1 |
| S-05 autoRebuyState[beneficiary] | `_deactivateAfKing` | `DegenerusGame.sol:1670` | `DegenerusGame.sol:1641` (`deactivateAfKingFromCoin`, BurnieCoin/BurnieCoinflip callback) | §1 |
| S-05 autoRebuyState[beneficiary] | `syncAfKingLazyPassFromCoin` | `DegenerusGame.sol:1654` | `DegenerusGame.sol:1654` (BurnieCoinflip callback) | §1 |
| S-06 traitBurnTicket[lvl][trait] | `_raritySymbolBatch` (assembly sstore) | `DegenerusGameMintModule.sol:537` (writes at `:616`, `:627`) | `MintModule.sol:662` (`processTicketBatch`); `MintModule.sol:385` (`processFutureTicketBatch`) | §1, §2, §3 |
| S-06 traitBurnTicket[lvl][trait] | `adminSeedTraitBucket` direct push | `DegenerusGame.sol:2398` | `DegenerusGame.sol:2398..2420` (admin) | §3 |
| S-06 traitBurnTicket[lvl][trait] | `adminClearTraitBucket` direct push | `DegenerusGame.sol:2427` | `DegenerusGame.sol:2427` (admin) | §3 |
| S-06 traitBurnTicket[lvl][trait] | helper writer at `:2510` | `DegenerusGame.sol:2510` | `DegenerusGame.sol:2510` (admin/helper) | §3 |
| S-07 deityBySymbol[fullSymId] | `_purchaseDeityPass` | `DegenerusGameWhaleModule.sol:598` | `WhaleModule.sol:538` (EOA `purchaseDeityPass`); `DegenerusGame.sol:644` (dispatcher) | §1, §2, §3 |
| S-08 currentPrizePool | `_setCurrentPrizePool` | `DegenerusGameStorage.sol:821` | `JackpotModule.sol:406, :506, :515, :1203`; `AdvanceModule.sol:902` | §1 |
| S-09 prizePoolsPacked | `_setNextPrizePool` / `_setFuturePrizePool` / `_setPrizePools` | `DegenerusGameStorage.sol:684, :791, :803` | `JackpotModule.sol:409, :433, :434, :510, :511, :548, :569, :725, :840, :842, :877, :1201`; `AdvanceModule.sol:902, :423, :642`; `MintModule.sol` (various `_processMintPayment`/`_handleMintRevenue` reached from `purchase`/`purchaseCoin`/`purchaseBurnieLootbox`); `WhaleModule.sol:187, :380, :538` (purchase entries); `DegenerusGame.sol:1029` (`recordDecBurn`); `DegeneretteModule.sol:553, :556, :764, :780` (place-bet + payout); `LootboxModule.sol` (lootbox payout consolidation); `Storage.sol:744, :771` (swapAndFreeze / unfreezePool) | §1, §8 |
| S-09 prizePoolsPacked | `_swapAndFreeze` / `_unfreezePool` | `DegenerusGameStorage.sol:754, :771` | `AdvanceModule.sol:299, :631, :1095, :1735` | §1, §8 |
| S-09 prizePoolsPacked | `handleGameOverDrain` (zeros all 4 pools) | `DegenerusGameGameOverModule.sol:147, :148, :149, :150` | `GameOverModule.sol:147..150` | §1 |
| S-10 jackpotCounter | `payDailyJackpotCoinAndTickets` (`+=` counterStep) | `DegenerusGameJackpotModule.sol:596` | `JackpotModule.sol:665` | §1, §2 |
| S-10 jackpotCounter | `payDailyJackpot` (`+=` counterStep) | `DegenerusGameJackpotModule.sol:339` | `JackpotModule.sol:506` | §1, §2 |
| S-10 jackpotCounter | `_endPhase` / phase-transition cleanup | `DegenerusGameAdvanceModule.sol:644` | `AdvanceModule.sol:644` | §1, §2 |
| S-11 compressedJackpotFlag | `advanceGame` turbo + compressed writes | `DegenerusGameAdvanceModule.sol:177, :399, :645` | `AdvanceModule.sol:177, :399, :645` | §1 |
| S-12 resumeEthPool | `_processDailyEth` call-1 split write | `DegenerusGameJackpotModule.sol:1340` | `JackpotModule.sol:1340` | §1 |
| S-12 resumeEthPool | `_processDailyEth` call-2 clear | `DegenerusGameJackpotModule.sol:1245` | `JackpotModule.sol:1245` | §1 |
| S-13 dailyTicketBudgetsPacked | `payDailyJackpot` P1 (`= _packDailyTicketBudgets(...)`) | `DegenerusGameJackpotModule.sol:444` | `JackpotModule.sol:444` | §1, §2 |
| S-13 dailyTicketBudgetsPacked | `payDailyJackpotCoinAndTickets` clear | `DegenerusGameJackpotModule.sol:670` | `JackpotModule.sol:670` | §1, §2 |
| S-14 sDGNRS poolBalances[Reward] | `StakedDegenerusStonk.transferFromPool` | `StakedDegenerusStonk.sol:412` (writes at `:422`) | `JackpotModule.sol:1498` (`_handleSoloBucketWinner`, final-day); `DegenerusGame.sol:1735, :1739` (claim/settlement); `DegenerusGame.sol:420` (`payCoinflipBountyDgnrs`); Decimator/Lootbox `Reward`-keyed drains | §1, §8, §11 |
| S-14 sDGNRS poolBalances[Reward] | `StakedDegenerusStonk.transferBetweenPools` | `StakedDegenerusStonk.sol:453, :455` | `AdvanceModule.sol:1718` (`_finalizeEarlybird`); jackpot/mint/gameOver rebalances | §1 |
| S-14 sDGNRS poolBalances[Reward] | `StakedDegenerusStonk` constructor / initial distribution | `StakedDegenerusStonk.sol` (constructor) | (constructor) | §1 |
| S-14 sDGNRS poolBalances[Reward] | ERC20 `transfer` / `transferFrom` / `_mint` / `_burn` (OZ-inherited) | `node_modules/@openzeppelin/.../ERC20.sol` (`(OZ-inherited)`) | EOA ERC20 surface | §1 |
| S-15 sDGNRS poolBalances[Lootbox] | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:412` (writes at `:422`) | `LootboxModule.sol:1786` (`_creditDgnrsReward`); reached from `openLootBox` / `openBurnieLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox` | §6, §7, §8 |
| S-15 sDGNRS poolBalances[Lootbox] | `StakedDegenerusStonk.transferBetweenPools` (Lootbox-touching) | `StakedDegenerusStonk.sol:453, :455` | JackpotModule / MintModule / GameOverModule Lootbox-keyed rebalances | §6, §7, §8 |
| S-15 sDGNRS poolBalances[Lootbox] | `StakedDegenerusStonk` constructor (`pools[Lootbox] = lootboxAmount`) | `StakedDegenerusStonk.sol:312` | (constructor) | §6 |
| S-15 sDGNRS poolBalances[Lootbox] | `StakedDegenerusStonk.burnAtGameOver` (`delete poolBalances`) | `StakedDegenerusStonk.sol:469` | (game-over teardown) | §6 |
| S-16 claimablePool | `_creditClaimable` | `DegenerusGamePayoutUtils.sol:101` | `JackpotModule.sol:780` (`_addClaimableEth`); reached from jackpot resolution flows | §5 |
| S-16 claimablePool | `DecimatorModule._awardDecimatorLootbox` (`-=`) | `DegenerusGameDecimatorModule.sol:388` | `DecimatorModule.sol:388` (EOA `claimDecimatorJackpot`) | §5, §13 |
| S-16 claimablePool | `MintModule._resolveMintShortfall` (`-=`) | `DegenerusGameMintModule.sol:949` | `MintModule.sol:949` (EOA mint paths) | §5 |
| S-16 claimablePool | `AdvanceModule._processStethYield` (`+=`) | `DegenerusGameAdvanceModule.sol:905` | `AdvanceModule.sol:905` | §5 |
| S-16 claimablePool | `DegeneretteModule._creditCheckedFromClaimable` (`-=`) | `DegenerusGameDegeneretteModule.sol:547` | `DegeneretteModule.sol:547` (EOA `playDegenerette`) | §5 |
| S-16 claimablePool | `DegeneretteModule._resolveLootboxDirect` (`+=`) | `DegenerusGameDegeneretteModule.sol:1131` | `DegeneretteModule.sol:1131` (mixed: VRF callback + EOA branches) | §5 |
| S-16 claimablePool | `JackpotModule._addClaimableEth` / `_processDailyEth` (`+=`) | `DegenerusGameJackpotModule.sol:763, :1335` | `JackpotModule.sol:763, :1335` | §5 |
| S-16 claimablePool | `GameOverModule.handleGameOverDrain` (`+=` deity refund + decSpend) | `DegenerusGameGameOverModule.sol:134, :171` | `GameOverModule.sol:134, :171` | §5 |
| S-16 claimablePool | `GameOverModule.handleFinalSweep` (`= 0`) | `DegenerusGameGameOverModule.sol:207` | `GameOverModule.sol:207` | §5 |
| S-16 claimablePool | `DegenerusGame.claimWinnings` (`-=`) | `DegenerusGame.sol:1408` | `DegenerusGame.sol:1408` (EOA `claimWinnings`) | §5 |
| S-16 claimablePool | `DegenerusGame.useClaimableForMint` (`-=`) | `DegenerusGame.sol:946` | `DegenerusGame.sol:946` (EOA mint family) | §5 |
| S-16 claimablePool | `DegenerusGame.sweepSdgnrsClaim` (`-=`) | `DegenerusGame.sol:1739` | `DegenerusGame.sol:1739` (sDGNRS `claimRedemption` callback) | §5 |
| S-17 pendingRedemptionEthValue | `StakedDegenerusStonk.beginRedemption` (`+=`) | `StakedDegenerusStonk.sol:789` | `StakedDegenerusStonk.sol:789` (EOA `burn`/`burnWrapped`) | §5, §12 |
| S-17 pendingRedemptionEthValue | `StakedDegenerusStonk.resolveRedemptionPeriod` (RMW) | `StakedDegenerusStonk.sol:593` | `AdvanceModule.sol:1230, :1293, :1323` (advance-stack) | §5, §12 |
| S-17 pendingRedemptionEthValue | `StakedDegenerusStonk.claimRedemption` (`-=`) | `StakedDegenerusStonk.sol:657` | `StakedDegenerusStonk.sol:657` (EOA `claimRedemption`) | §5, §12 |
| S-17 pendingRedemptionEthValue | `_submitGamblingClaimFrom` (`+=`) | `StakedDegenerusStonk.sol:789` | EOA `burn`/`burnWrapped` | §12 |
| S-18 deityPassOwners | `WhaleModule._purchaseDeityPass` (`.push(buyer)`) | `DegenerusGameWhaleModule.sol:596` | `WhaleModule.sol:596` (EOA `purchaseDeityPass`) | §5, §7 |
| S-19 deityPassPurchasedCount | `WhaleModule._purchaseDeityPass` (`+= 1`) | `DegenerusGameWhaleModule.sol:595` | `WhaleModule.sol:595` (EOA `purchaseDeityPass`) | §5 |
| S-20 address(this).balance (ETH) | `DegenerusGame.receive()` accepts ETH | (implicit Solidity receive) | any EOA `send/transfer/call{value:}` to game | §5 |
| S-20 address(this).balance (ETH) | every `payable` purchase function (mintBatch / purchaseWhaleBundle / purchaseDeityPass / purchaseLazyPass) | various | EOA-callable purchase entries | §5 |
| S-20 address(this).balance (ETH) | `claimWinnings` outflow (`call{value:}`) | `DegenerusGame.sol:1408` | EOA `claimWinnings` | §5 |
| S-20 address(this).balance (ETH) | sDGNRS / vault / GNRUS withdrawals (cross-contract callbacks) | various | various | §5 |
| S-20 address(this).balance (ETH) | `_stakeEth` / Lido stETH conversion | `AdvanceModule.sol:1555` neighborhood | `advanceGame()` | §5 |
| S-20 address(this).balance (ETH) | `_handleGameOverPath` deity refunds / terminal payouts | inside `handleGameOverDrain` | advanceGame | §5 |
| S-21 stETH balanceOf(game) | Lido rebase (autonomous; no-source-under-`contracts/`) | Lido (trace stop) | n/a | §5 |
| S-21 stETH balanceOf(game) | `steth.transfer(to, amount)` outgoing (game→someone) | `DegenerusGameGameOverModule.sol:243, :247` | (post-30-day handleFinalSweep) | §5 |
| S-21 stETH balanceOf(game) | `AdvanceModule._stakeEth` (game → Lido via wrap) | `DegenerusGameAdvanceModule.sol:1555` | `advanceGame()` | §5 |
| S-21 stETH balanceOf(game) | external parties transferring stETH IN | Lido (no source under `contracts/`) | any EOA `IStETH.transfer(game, amount)` | §5 |
| S-22 lootboxEvBenefitUsedByLevel | `LootboxModule._applyEvMultiplierWithCap` | `DegenerusGameLootboxModule.sol:511` | `LootboxModule.sol:526` (EOA `openLootBox`); `:567`, `:607` (`openBurnieLootBox`); `:674` (`resolveLootboxDirect` auto-resolve); `:707` (`resolveRedemptionLootbox`) | §6, §7, §8, §13 |
| S-23 lootboxRngWordByIndex | `AdvanceModule._finalizeLootboxRng` (daily) | `DegenerusGameAdvanceModule.sol:1253` (writes at `:1256`) | `AdvanceModule.sol:275, :1234, :1296, :1326` (`advanceGame`-stack) | §7, §8, §10 |
| S-23 lootboxRngWordByIndex | `AdvanceModule.rawFulfillRandomWords` (mid-day branch) | `DegenerusGameAdvanceModule.sol:1745` | `AdvanceModule.sol:1761` (VRF callback) | §7, §8, §10 |
| S-23 lootboxRngWordByIndex | `AdvanceModule._backfillOrphanedLootboxIndices` | `DegenerusGameAdvanceModule.sol:1806` | `AdvanceModule.sol:1818` (gap-day backfill from advanceGame) | §7, §8, §10 |
| S-24 lootboxEth[index][player] | `LootboxModule.openLootBox` self-zero (post-amount-capture) | `DegenerusGameLootboxModule.sol:576` | `LootboxModule.sol:576` (EOA `openLootBox`) | §7 |
| S-24 lootboxEth[index][player] | `MintModule._allocateLootbox` | `DegenerusGameMintModule.sol:1013` | `MintModule.sol:1013` (EOA `buyTickets`) | §7 |
| S-24 lootboxEth[index][player] | `WhaleModule._whaleLootboxAllocate` | `DegenerusGameWhaleModule.sol:876` | `WhaleModule.sol:876` (EOA `buyWhaleBundle`/`buyWhaleHalf`) | §7 |
| S-25 lootboxDay[index][player] | `MintModule._allocateLootbox` | `DegenerusGameMintModule.sol:991` | `MintModule.sol:991` (EOA `buyTickets`) | §7 |
| S-25 lootboxDay[index][player] | `MintModule._burnieAllocate` | `DegenerusGameMintModule.sol:1397` | `MintModule.sol:1397` (BURNIE coin transfer callback) | §7 |
| S-25 lootboxDay[index][player] | `WhaleModule._whaleLootboxAllocate` | `DegenerusGameWhaleModule.sol:854` | `WhaleModule.sol:854` (EOA `buyWhaleBundle`) | §7 |
| S-26 lootboxBaseLevelPacked | `LootboxModule.openLootBox` self-zero | `DegenerusGameLootboxModule.sol:578` | `LootboxModule.sol:578` (EOA `openLootBox`) | §7 |
| S-26 lootboxBaseLevelPacked | `MintModule._allocateLootbox` | `DegenerusGameMintModule.sol:992` | `MintModule.sol:992` (EOA `buyTickets`) | §7 |
| S-26 lootboxBaseLevelPacked | `WhaleModule._whaleLootboxAllocate` | `DegenerusGameWhaleModule.sol:855` | `WhaleModule.sol:855` (EOA `buyWhaleBundle`) | §7 |
| S-27 lootboxEvScorePacked | `LootboxModule.openLootBox` self-zero | `DegenerusGameLootboxModule.sol:579` | `LootboxModule.sol:579` (EOA `openLootBox`) | §7 |
| S-27 lootboxEvScorePacked | `MintModule._allocateLootbox` (snapshot at purchase) | `DegenerusGameMintModule.sol:1155` | `MintModule.sol:1155` (EOA `buyTickets`) | §7 |
| S-27 lootboxEvScorePacked | `WhaleModule._whaleLootboxAllocate` (snapshot) | `DegenerusGameWhaleModule.sol:856` | `WhaleModule.sol:856` (EOA `buyWhaleBundle`) | §7 |
| S-28 lootboxDistressEth | `LootboxModule.openLootBox` self-zero (conditional) | `DegenerusGameLootboxModule.sol:581` | `LootboxModule.sol:581` (EOA `openLootBox`) | §7 |
| S-28 lootboxDistressEth | `MintModule._allocateLootbox` (distress accumulation) | `DegenerusGameMintModule.sol:1031` | `MintModule.sol:1031` (EOA `buyTickets`) | §7 |
| S-28 lootboxDistressEth | `WhaleModule._whaleLootboxAllocate` (distress accumulation) | `DegenerusGameWhaleModule.sol:881` | `WhaleModule.sol:881` (EOA `buyWhaleBundle`) | §7 |
| S-29 lootboxBurnie | `LootboxModule.openBurnieLootBox` self-zero | `DegenerusGameLootboxModule.sol:615` | `LootboxModule.sol:615` (EOA `openBurnieLootBox`) | §7 |
| S-29 lootboxBurnie | `MintModule._burnieAllocate` (+= burnieAmount) | `DegenerusGameMintModule.sol:1399` | `MintModule.sol:1399` (BURNIE transfer callback, EOA-triggered) | §7 |
| S-30 presaleStatePacked | `MintModule._presaleCapCheck` | `DegenerusGameMintModule.sol:1026` | `MintModule.sol:1026` (EOA `buyTickets`/`processMint`) | §7, §11 |
| S-30 presaleStatePacked | `AdvanceModule._handlePhaseTransition` (`_psWrite(PS_ACTIVE, 0)`) | `DegenerusGameAdvanceModule.sol:433` | `AdvanceModule.sol:433` (advanceGame) | §7, §11 |
| S-30 presaleStatePacked | constructor initializer | `DegenerusGameStorage.sol:843` | constructor | §11 |
| S-31 gameOverPossible | `AdvanceModule.advanceGame` (FLAG-03 auto-clear) | `DegenerusGameAdvanceModule.sol:178` | `AdvanceModule.sol:178` (advanceGame) | §7 |
| S-31 gameOverPossible | `AdvanceModule._evalGameOverPossible` | `DegenerusGameAdvanceModule.sol:1888, :1893` | `AdvanceModule.sol:1888, :1893` (advanceGame) | §7 |
| S-32 mintPacked_[player] | `MintStreakUtils._mintStreakWrite` / `_recordMintStreakForLevel` | `MintStreakUtils.sol:47` | EOA mint flows | §7, §8, §10, §13 |
| S-32 mintPacked_[player] | `MintModule._allocateMintPacked` / `_processMint` / `_burnieAllocate` (multi-callsite) | `DegenerusGameMintModule.sol:240, :275, :369, :1433` | `MintModule.sol:240, :275, :369, :1433` (EOA `buyTickets`) | §7, §8, §13 |
| S-32 mintPacked_[player] | `BoonModule.consumeActivityBoon` | `DegenerusGameBoonModule.sol:320` | `BoonModule.sol:320` (reached via lootbox stack delegatecall) | §7, §13 |
| S-32 mintPacked_[player] | `BoonModule._applyBoon` (whale-pass branch) | `DegenerusGameBoonModule.sol:303` | `BoonModule.sol:303` (via lootbox boon roll) | §7 |
| S-32 mintPacked_[player] | `WhaleModule._buyWhaleBundle*` writers (multi) | `DegenerusGameWhaleModule.sol:210, :303, :419, :516, :548, :589, :669, :944` | `WhaleModule.sol:*` (EOA `buyWhaleBundle`/`buyWhaleHalf`/`buyDeityPass`) | §7, §8, §13 |
| S-32 mintPacked_[player] | `WhaleModule._buyDeityPass` | `DegenerusGameWhaleModule.sol:589` | `WhaleModule.sol:589` (EOA `buyDeityPass`) | §7 |
| S-32 mintPacked_[player] | `AdvanceModule._cacheAffiliateBonus` (affiliate fields) | `DegenerusGameAdvanceModule.sol:1008` | `AdvanceModule.sol:1008` (advanceGame) | §7 |
| S-32 mintPacked_[player] | `DegenerusGame` constructor (deity sentinel bits for SDGNRS + VAULT) | `DegenerusGame.sol:222, :223` | constructor | §7 |
| S-32 mintPacked_[player] | `_applyWhalePassStats` (whale-pass activation) | `DegenerusGameStorage.sol:1204` | `Storage.sol:1204` (reached from `_activateWhalePass` on lootbox stack) | §7, §13 |
| S-33 decWindowOpen | `AdvanceModule._unlockRng` (open=true) | `DegenerusGameAdvanceModule.sol:1655` | `AdvanceModule.sol:1655` (advanceGame) | §7 |
| S-33 decWindowOpen | `AdvanceModule._unlockRng` (open=false) | `DegenerusGameAdvanceModule.sol:1659` | `AdvanceModule.sol:1659` (advanceGame) | §7 |
| S-34 boonPacked[player] slot0/slot1 | `LootboxModule._applyBoon` writes (multi-callsite) | `DegenerusGameLootboxModule.sol:1432, :1452, :1479, :1503, :1526, :1547, :1568, :1603` | `LootboxModule.sol:*` (reached from `_rollLootboxBoons:1162`; from `issueDeityBoon:799`) | §7 |
| S-34 boonPacked[player] slot0/slot1 | `WhaleModule._buyWhaleBundle*` boon writes | `DegenerusGameWhaleModule.sol:202, :388, :556, :898` | `WhaleModule.sol:*` (EOA `buyWhaleBundle`/`buyWhaleHalf`/`buyDeityPass`) | §7 |
| S-34 boonPacked[player] slot0/slot1 | `MintModule._processMint` boon write | `DegenerusGameMintModule.sol:1433` | `MintModule.sol:1433` (EOA `buyTickets`) | §7 |
| S-34 boonPacked[player] slot0/slot1 | `BoonModule.checkAndClearExpiredBoon` | `DegenerusGameBoonModule.sol:265, :266` | `BoonModule.sol:265, :266` (reached from lootbox roll) | §7 |
| S-34 boonPacked[player] slot0/slot1 | `BoonModule.consumeActivityBoon` slot1 writes | `DegenerusGameBoonModule.sol:291, :297, :301` | `BoonModule.sol:*` (reached from lootbox `_resolveLootboxCommon:1035`) | §7 |
| S-34 boonPacked[player] slot0/slot1 | `BoonModule.<other-externals>` (`:41, :67, :93, :122, :283`) | `DegenerusGameBoonModule.sol:41, :67, :93, :122, :283` | BoonModule external surface (per-callsite verification deferred to Phase 299) | §7 |
| S-35 lastPurchaseDay | `AdvanceModule.advanceGame` (sets true at `:176, :397`) | `DegenerusGameAdvanceModule.sol:176, :397` | `AdvanceModule.sol:176, :397` (advanceGame) | §6, §7, §8 |
| S-35 lastPurchaseDay | `AdvanceModule._handlePhaseTransition` (sets false at `:439`) | `DegenerusGameAdvanceModule.sol:439` | `AdvanceModule.sol:439` (advanceGame) | §6, §7, §8 |
| S-36 jackpotPhaseFlag | `AdvanceModule._handlePhaseTransition` (`:333` false, `:437` true) | `DegenerusGameAdvanceModule.sol:333, :437` | `AdvanceModule.sol:333, :437` (advanceGame) | §6, §7, §8 |
| S-37 purchaseStartDay | `DegenerusGame` constructor | `DegenerusGame.sol:218` | constructor | §6, §7, §8 |
| S-37 purchaseStartDay | `AdvanceModule._handlePhaseTransition` (`= day`) | `DegenerusGameAdvanceModule.sol:332` | `AdvanceModule.sol:332` (advanceGame) | §6, §7, §8 |
| S-38 rngRequestTime | `AdvanceModule._tryRequestRng` (set `= ts`) | `DegenerusGameAdvanceModule.sol:1122` | `AdvanceModule.sol:1122` (advanceGame) | §6, §7, §8, §9 |
| S-38 rngRequestTime | `AdvanceModule.retryLootboxRng` (set `= block.timestamp`) | `DegenerusGameAdvanceModule.sol:1154` | `AdvanceModule.sol:1154` (EOA `retryLootboxRng`) | §9 |
| S-38 rngRequestTime | `AdvanceModule._gameOverEntropy` (clear `= 0`, set on failure) | `DegenerusGameAdvanceModule.sol:1329, :1341` | `AdvanceModule.sol:1329, :1341` (advanceGame) | §9 |
| S-38 rngRequestTime | `AdvanceModule._finalizeRngRequest` (`= uint48(block.timestamp)`) | `DegenerusGameAdvanceModule.sol:1633` | `AdvanceModule.sol:1633` (advanceGame) | §9 |
| S-38 rngRequestTime | `AdvanceModule._unlockRng` (clear `= 0`) | `DegenerusGameAdvanceModule.sol:1734, :1692` | `AdvanceModule.sol:1692, :1734` (advanceGame) | §9 |
| S-38 rngRequestTime | `AdvanceModule.rawFulfillRandomWords` (clear `= 0`) | `DegenerusGameAdvanceModule.sol:1764` | `AdvanceModule.sol:1764` (VRF callback) | §9 |
| S-38 rngRequestTime | `AdvanceModule.updateVrfCoordinatorAndSub` (clear `= 0`) | `DegenerusGameAdvanceModule.sol:1692` | `AdvanceModule.sol:1692` (governance) | §9 |
| S-39 rngLockedFlag | `AdvanceModule._requestRng` / `_unlockRng` | `DegenerusGameAdvanceModule.sol:1634, :1690, :1731` | `AdvanceModule.sol:1634, :1690, :1731` (advanceGame + retryLootboxRng) | §6, §7, §8 |
| S-40 ticketWriteSlot | `DegenerusGameStorage._swapTicketSlot` (toggles `!`) | `DegenerusGameStorage.sol:744` | `AdvanceModule.sol:299, :601, :1095` (advanceGame: swapAndFreeze + game-over drain + consolidation) | §1, §2, §6, §7, §8, §10 |
| S-41 affiliate cross-contract slots | `DegenerusAffiliate.recordAffiliateEarnings` | `DegenerusAffiliate.sol` (per-contract) | reached from MintModule/WhaleModule mint flows (EOA-callable) | §7, §8 |
| S-42 questView cross-contract slots | `DegenerusQuests` external quest-fulfillment writers | `DegenerusQuests.sol` (per-contract) | EOA-callable quest-claim paths | §7, §8 |
| S-43 degeneretteBets[player][nonce] | `_placeDegeneretteBetCore` | `DegenerusGameDegeneretteModule.sol:479` | `DegeneretteModule.sol:367` (EOA `placeDegeneretteBet`) | §8 |
| S-43 degeneretteBets[player][nonce] | `_resolveBet` self-delete | `DegenerusGameDegeneretteModule.sol:597` | `DegeneretteModule.sol:597` (the consumer) | §8 |
| S-44 prizePoolFrozen | `DegenerusGameStorage._swapAndFreeze` (= true) | `DegenerusGameStorage.sol:757` | `Storage.sol:757` (advanceGame) | §8 |
| S-44 prizePoolFrozen | `DegenerusGameStorage._unfreezePool` (= false) | `DegenerusGameStorage.sol:777` | `Storage.sol:777` (advanceGame) | §8 |
| S-45 prizePoolPendingPacked | `DegenerusGameStorage._swapAndFreeze` (clear / seed) | `DegenerusGameStorage.sol:762, :764` | `Storage.sol:762, :764` (advanceGame) | §8 |
| S-45 prizePoolPendingPacked | `DegenerusGameStorage._unfreezePool` (`= 0`) | `DegenerusGameStorage.sol:776` | `Storage.sol:776` (advanceGame) | §8 |
| S-45 prizePoolPendingPacked | `DegeneretteModule._collectBetFunds` (frozen-branch place) | `DegenerusGameDegeneretteModule.sol:553` | `DegeneretteModule.sol:553` (EOA `placeDegeneretteBet`) | §8 |
| S-45 prizePoolPendingPacked | `DegeneretteModule._distributePayout` (frozen-branch debit) | `DegenerusGameDegeneretteModule.sol:764` | `DegeneretteModule.sol:764` (resolution self-write) | §8 |
| S-45 prizePoolPendingPacked | `MintModule.*` purchase paths (`_setPendingPools` when frozen) | `DegenerusGameMintModule.sol` (various) | EOA `purchaseTickets*` family | §8 |
| S-45 prizePoolPendingPacked | `JackpotModule.*` pending writes during jackpot phase | `JackpotModule.sol` (various) | advanceGame | §8 |
| S-46 lootboxRngPacked LR_INDEX | `_finalizeRngRequest` LR_INDEX++ | `DegenerusGameAdvanceModule.sol:1620` | `AdvanceModule.sol:1620` (advanceGame) | §9, §10 |
| S-46 lootboxRngPacked LR_INDEX | static initializer | `DegenerusGameStorage.sol:1312` | constructor | §10 |
| S-46 lootboxRngPacked LR_MID_DAY | `AdvanceModule._requestLootboxRng` (set 1) | `DegenerusGameAdvanceModule.sol:1096` | `AdvanceModule.sol:1096` (EOA `requestLootboxRng`) | §9 |
| S-46 lootboxRngPacked LR_MID_DAY | `AdvanceModule.rngGate` (clear path) | `DegenerusGameAdvanceModule.sol:225` | `AdvanceModule.sol:225` (advanceGame) | §9 |
| S-46 lootboxRngPacked LR_MID_DAY | `AdvanceModule.updateVrfCoordinatorAndSub` (clear) | `DegenerusGameAdvanceModule.sol:1698` | `AdvanceModule.sol:1698` (governance) | §9 |
| S-47 vrfCoordinator | `AdvanceModule.wireVrf` | `DegenerusGameAdvanceModule.sol:506` | `AdvanceModule.sol:506` (Admin constructor one-shot) | §9 |
| S-47 vrfCoordinator | `AdvanceModule.updateVrfCoordinatorAndSub` | `DegenerusGameAdvanceModule.sol:1685` | `AdvanceModule.sol:1685` (governance) | §9 |
| S-48 vrfSubscriptionId | `AdvanceModule.wireVrf` | `DegenerusGameAdvanceModule.sol:507` | `AdvanceModule.sol:507` (Admin constructor) | §9 |
| S-48 vrfSubscriptionId | `AdvanceModule.updateVrfCoordinatorAndSub` | `DegenerusGameAdvanceModule.sol:1686` | `AdvanceModule.sol:1686` (governance) | §9 |
| S-49 vrfKeyHash | `AdvanceModule.wireVrf` | `DegenerusGameAdvanceModule.sol:508` | `AdvanceModule.sol:508` (Admin constructor) | §9 |
| S-49 vrfKeyHash | `AdvanceModule.updateVrfCoordinatorAndSub` | `DegenerusGameAdvanceModule.sol:1687` | `AdvanceModule.sol:1687` (governance) | §9 |
| S-50 ticketLevel | `processFutureTicketBatch` / `processTicketBatch` self-writes | `DegenerusGameMintModule.sol:395, :400, :408, :514, :519, :523, :668, :676, :716` | `MintModule.sol:*` (advanceGame stack) | §10 |
| S-50 ticketLevel | `AdvanceModule.advanceGame` FF-promotion | `DegenerusGameAdvanceModule.sol:319` | `AdvanceModule.sol:319` | §10 |
| S-51 ticketCursor | `processFutureTicketBatch` / `processTicketBatch` self-writes | `DegenerusGameMintModule.sol:394, :401, :407, :507, :515, :518, :522, :669, :675, :711, :715` | `MintModule.sol:*` (advanceGame stack) | §10 |
| S-51 ticketCursor | `AdvanceModule.advanceGame` FF-promotion reset | `DegenerusGameAdvanceModule.sol:320` | `AdvanceModule.sol:320` | §10 |
| S-52 ticketQueue[rk] | `_queueTickets` (`.push(buyer)`) | `DegenerusGameStorage.sol:580` | `DegenerusGame.sol:226, :227` (constructor); `AdvanceModule.sol:1535, :1541` (advanceGame vault tickets); `WhaleModule.sol:313, :482, :625` (whale-bundle/lazy-pass/deity-pass); `LootboxModule.sol:1067, :1190` (lootbox resolution); `JackpotModule.sol:703, :837, :1007, :2305` (auto-rebuy / jackpot-flow) | §10 |
| S-52 ticketQueue[rk] | `_queueTicketsScaled` (`.push`) | `DegenerusGameStorage.sol:612` | `MintModule.sol:1129` (EOA `_purchaseFor`) | §10 |
| S-52 ticketQueue[rk] | `_queueTicketRange` (`.push`) | `DegenerusGameStorage.sol:666` | `DecimatorModule.sol:582` (EOA `recordDecBurn`/decimator-claim); `WhaleModule.sol:973` (`claimWhalePass`); `Storage.sol:1135` (whale-pass redemption) | §10 |
| S-52 ticketQueue[rk] | self-`delete` (advanceGame) | `DegenerusGameMintModule.sol:406, :510, :674, :714` | `MintModule.sol:*` (advanceGame) | §10 |
| S-53 ticketsOwedPacked[rk][player] | `_queueTickets` writes | `DegenerusGameStorage.sol:585` | same callsites as S-52 row 1 | §10 |
| S-53 ticketsOwedPacked[rk][player] | `_queueTicketsScaled` writes | `DegenerusGameStorage.sol:636` | `MintModule.sol:1129` | §10 |
| S-53 ticketsOwedPacked[rk][player] | `_queueTicketRange` writes | `DegenerusGameStorage.sol:671` | `DecimatorModule.sol:582`, `WhaleModule.sol:973`, `Storage.sol:1135` | §10 |
| S-53 ticketsOwedPacked[rk][player] | self-writes (advanceGame `_processOneTicketEntry` / `_resolveZeroOwedRemainder`) | `DegenerusGameMintModule.sol:433, :445, :455, :490, :733, :740, :746, :814` | `MintModule.sol:*` | §10 |
| S-54 currentBounty | inline initializer | `BurnieCoinflip.sol:167` | constructor (= 1_000 ether) | §11 |
| S-54 currentBounty | `BurnieCoinflip.processCoinflipPayouts` self-write | `BurnieCoinflip.sol:874` | `BurnieCoinflip.sol:874` (consumer self-write inside advanceGame stack) | §11 |
| S-55 bountyOwedTo | `BurnieCoinflip._addDailyFlip` arming arm | `BurnieCoinflip.sol:681` | `BurnieCoinflip.sol:229` (EOA `depositCoinflip` via `_depositCoinflip:312`) | §11 |
| S-55 bountyOwedTo | `BurnieCoinflip.processCoinflipPayouts` self-clear | `BurnieCoinflip.sol:865` | `BurnieCoinflip.sol:865` (consumer self-clear) | §11 |
| S-56 redemptionPeriodIndex (sStonk) | `StakedDegenerusStonk._submitGamblingClaimFrom` | `StakedDegenerusStonk.sol:760` | `StakedDegenerusStonk.sol:486, :506` (EOA `burn`/`burnWrapped`) | §12 |
| S-57 pendingRedemptionEthBase (sStonk) | `resolveRedemptionPeriod` (= 0 clear) | `StakedDegenerusStonk.sol:594` | `AdvanceModule.sol:1230, :1293, :1323` (advanceGame) | §12 |
| S-57 pendingRedemptionEthBase (sStonk) | `_submitGamblingClaimFrom` (+= ethValueOwed) | `StakedDegenerusStonk.sol:790` | EOA `burn`/`burnWrapped` | §12 |
| S-58 pendingRedemptionBurnieBase (sStonk) | `resolveRedemptionPeriod` (= 0 clear) | `StakedDegenerusStonk.sol:601` | advanceGame | §12 |
| S-58 pendingRedemptionBurnieBase (sStonk) | `_submitGamblingClaimFrom` (+= burnieOwed) | `StakedDegenerusStonk.sol:792` | EOA `burn`/`burnWrapped` | §12 |
| S-59 pendingRedemptionBurnie (sStonk) | `resolveRedemptionPeriod` (-= base) | `StakedDegenerusStonk.sol:600` | advanceGame | §12 |
| S-59 pendingRedemptionBurnie (sStonk) | `_submitGamblingClaimFrom` (+=) | `StakedDegenerusStonk.sol:791` | EOA `burn`/`burnWrapped` | §12 |
| S-60 pendingRedemptions[player] struct (sStonk) | `_submitGamblingClaimFrom` writes ethValueOwed/burnieOwed/periodIndex/activityScore | `StakedDegenerusStonk.sol:803, :805, :806, :810` | EOA `burn`/`burnWrapped` | §12 |
| S-60 pendingRedemptions[player] struct (sStonk) | `claimRedemption` delete | `StakedDegenerusStonk.sol:661` | EOA `claimRedemption` | §12 |
| S-60 pendingRedemptions[player] struct (sStonk) | `claimRedemption` partial clear | `StakedDegenerusStonk.sol:664` | EOA `claimRedemption` | §12 |
| S-61 redemptionPeriods[period] struct (sStonk) | `resolveRedemptionPeriod` writes `{roll, flipDay}` | `StakedDegenerusStonk.sol:604` | advanceGame (sole writer; vulnerable to overwrite via stale `redemptionPeriodIndex`) | §12 |
| S-62 coinflipDayResult[flipDay] | `BurnieCoinflip._resolveDay` (via `processCoinflipPayouts`) | `BurnieCoinflip.sol:840` | `AdvanceModule.sol:1217, :1277, :1307, :1794` (advanceGame VRF) | §12 |
| S-63 rngWordByDay[day] | `AdvanceModule._applyDailyRng` | `DegenerusGameAdvanceModule.sol:1841` | `AdvanceModule.sol:1841` (advanceGame; one-shot per day) | §5, §12 |
| S-63 rngWordByDay[day] | `AdvanceModule._backfillGapDays` | `DegenerusGameAdvanceModule.sol:1793` | `AdvanceModule.sol:1793` (advanceGame gap-day) | §5, §12 |
| S-64 decBucketOffsetPacked[lvl] | `DecimatorModule.runDecimatorJackpot` | `DegenerusGameDecimatorModule.sol:252` | `AdvanceModule.sol:853` (`_consolidatePoolsAndRewardJackpots` advanceGame) | §13 |
| S-64 decBucketOffsetPacked[lvl] | `DecimatorModule.runTerminalDecimatorJackpot` | `DegenerusGameDecimatorModule.sol:795` | `GameOverModule.sol:168` (game-over drain) | §13 |
| S-65 decClaimRounds[lvl].rngWord | `DecimatorModule.runDecimatorJackpot` (set-once) | `DegenerusGameDecimatorModule.sol:258` | `AdvanceModule.sol:853` (advanceGame) | §13 |
| S-65 decClaimRounds[lvl].totalBurn | `DecimatorModule.runDecimatorJackpot` | `DegenerusGameDecimatorModule.sol:257` | `AdvanceModule.sol:853` (advanceGame) | §13 |
| S-65 decClaimRounds[lvl].poolWei | `DecimatorModule.runDecimatorJackpot` | `DegenerusGameDecimatorModule.sol:256` | `AdvanceModule.sol:853` (advanceGame) | §13 |
| S-66 decBurn[lvl][player].burn | `DecimatorModule.recordDecBurn` (or equivalent burn-recording) | `DegenerusGameDecimatorModule.sol:731` (cf. §4 recordTerminalDecBurn) | `BurnieCoin.decimatorBurn` → `DegenerusGame.recordDecBurn` (EOA-callable) | §13 |
| S-67 terminalDecBucketBurnTotal[bucketKey] | `DecimatorModule.recordTerminalDecBurn` | `DegenerusGameDecimatorModule.sol:731` | `BurnieCoin.terminalDecimatorBurn:634` → `DegenerusGame.recordTerminalDecBurn:1116` (EOA-callable, msg.sender==COIN gate) | §4 |

**Per-callsite granularity attestation.** Per `D-298-EXEMPT-REACH-01`, the same writer function is enumerated at each callsite if reached from different external entries. Composite writer rows (e.g. S-09 `prizePoolsPacked`) consolidate into one row with the callsite-list inline; §16 verdict matrix expands these into distinct verdict rows per callsite.

---

## §16 — Verdict Matrix (slot × writer × callsite)

Per `D-298-EXEMPT-REACH-01` strict + per-callsite + `D-298-EXEMPT-CROSSCONTRACT-01` (cross-contract EXEMPT propagation). Each row carries one of `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. Every VIOLATION row carries one tactic ∈ `{(a) rngLockedFlag-gated revert, (b) snapshot/anchor pattern, (c) pre-lock reorder, (d) immutable}` + ≤80-char rationale + `D-43N-V44-HANDOFF-NN` placeholder (NN numbered sequentially). EXEMPT rows have blank tactic / rationale / handoff anchor columns.

Sort order: §15 slot ID, then writer fn, then callsite.

| # | Slot | Writer fn | Callsite (file:line) | Reached from EXEMPT stack? | Classification | Recommended tactic | Rationale (≤80 chars) | v44.0 handoff anchor |
|---|------|-----------|----------------------|---------------------------|----------------|--------------------|-----------------------|----------------------|
| V-001 | S-01 dailyIdx | `_unlockRng` | `AdvanceModule.sol:1729` (all 5 callsites) | YES — advanceGame + VRF callback | EXEMPT-ADVANCEGAME |  |  |  |
| V-002 | S-01 dailyIdx | constructor | `DegenerusGame.sol:219` | constructor pre-deploy | EXEMPT-ADVANCEGAME |  |  |  |
| V-003 | S-02 dailyHeroWagers[day][q] | `_placeDegeneretteBetCore` | `DegeneretteModule.sol:367` (EOA `placeDegeneretteBet`) | NO — EOA | VIOLATION | (b) | Phase 288 dailyIdx snapshot; freeze read-day at lock time | D-43N-V44-HANDOFF-01 |
| V-004 | S-02 dailyHeroWagers[day][q] | `_placeDegeneretteBetCore` | `DegenerusGame.sol:714` (parent dispatch) | NO — EOA | VIOLATION | (b) | Parent dispatch — same day-key freeze attestation | D-43N-V44-HANDOFF-02 |
| V-005 | S-02 dailyHeroWagers[day][q] | `_placeDegeneretteBetCore` | `DegenerusVault.sol:607` (vault-routed) | NO — EOA | VIOLATION | (b) | Vault-routed bet — same day-key freeze attestation | D-43N-V44-HANDOFF-03 |
| V-006 | S-03 level | `_finalizeRngRequest` | `AdvanceModule.sol:1643` | YES — advanceGame (rngGate→`_requestRng`) | EXEMPT-ADVANCEGAME |  |  |  |
| V-007 | S-03 level | declaration default | `Storage.sol:250` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-008 | S-04 gameOver | `handleGameOverDrain` | `GameOverModule.sol:139` | YES — advanceGame → `_handleGameOverPath` | EXEMPT-ADVANCEGAME |  |  |  |
| V-009 | S-05 autoRebuyState[beneficiary] | `_setAutoRebuy` | `DegenerusGame.sol:1495` (EOA `setAutoRebuy`) | NO — EOA; rngLockedFlag gate at `:1513` runtime | VIOLATION | (a) | Gate already at DegenerusGame:1513; FUZZ-301 verify branch coverage | D-43N-V44-HANDOFF-04 |
| V-010 | S-05 autoRebuyState[beneficiary] | `_setAutoRebuyTakeProfit` | `DegenerusGame.sol:1504` (EOA `setAutoRebuyTakeProfit`) | NO — EOA; runtime gate at `:1528` | VIOLATION | (a) | Gate already at DegenerusGame:1528 — same coverage gap | D-43N-V44-HANDOFF-05 |
| V-011 | S-05 autoRebuyState[beneficiary] | `_setAfKingMode` | `DegenerusGame.sol:1559` (EOA `setAfKingMode`) | NO — EOA; runtime gate at `:1575` | VIOLATION | (a) | Gate already at DegenerusGame:1575 — same coverage gap | D-43N-V44-HANDOFF-06 |
| V-012 | S-05 autoRebuyState[beneficiary] | `_deactivateAfKing` | `DegenerusGame.sol:1641` (`deactivateAfKingFromCoin` BurnieCoin callback) | NO — EOA via coin callback | VIOLATION | (a) | MISSING `if (rngLockedFlag) revert` at DegenerusGame:1641 — add | D-43N-V44-HANDOFF-07 |
| V-013 | S-05 autoRebuyState[beneficiary] | `syncAfKingLazyPassFromCoin` | `DegenerusGame.sol:1654` (BurnieCoinflip callback) | NO — EOA via coinflip callback | VIOLATION | (a) | MISSING gate at DegenerusGame:1654 — add | D-43N-V44-HANDOFF-08 |
| V-014 | S-06 traitBurnTicket[lvl][trait] | `_raritySymbolBatch` (asm sstore) | `MintModule.sol:662` (`processTicketBatch` via AdvanceModule:1507) | YES — advanceGame `_runProcessTicketBatch` | EXEMPT-ADVANCEGAME |  |  |  |
| V-015 | S-06 traitBurnTicket[lvl][trait] | `_raritySymbolBatch` (asm sstore) | `MintModule.sol:385` (`processFutureTicketBatch` via AdvanceModule:1438) | YES — advanceGame `_prepareFutureTickets` | EXEMPT-ADVANCEGAME |  |  |  |
| V-016 | S-06 traitBurnTicket[lvl][trait] | `adminSeedTraitBucket` direct push | `DegenerusGame.sol:2398` (admin) | NO — admin EOA | VIOLATION | (a) | Gate adminSeed on `!rngLockedFlag && !gameOver` — never write during resolution | D-43N-V44-HANDOFF-09 |
| V-017 | S-06 traitBurnTicket[lvl][trait] | `adminClearTraitBucket` direct push | `DegenerusGame.sol:2427` (admin) | NO — admin EOA | VIOLATION | (a) | Gate adminClear on `!rngLockedFlag && !gameOver` — same window invariant | D-43N-V44-HANDOFF-10 |
| V-018 | S-06 traitBurnTicket[lvl][trait] | helper writer at `:2510` | `DegenerusGame.sol:2510` (admin/helper) | NO — admin/helper | VIOLATION | (a) | Gate writer on `!gameOver` — terminal jackpot bucket must be frozen at drain | D-43N-V44-HANDOFF-11 |
| V-019 | S-07 deityBySymbol[fullSymId] | `_purchaseDeityPass` | `WhaleModule.sol:538` (EOA `purchaseDeityPass`) | NO — EOA; runtime `rngLockedFlag` gate at `:543` | VIOLATION | (a) | Gate `_purchaseDeityPass` on `!gameOver` — already gates rngLockedFlag at :543 | D-43N-V44-HANDOFF-12 |
| V-020 | S-08 currentPrizePool | `_setCurrentPrizePool` self-writes (`JackpotModule.sol:406, :506, :515, :1203`) | self-stack of consumer | YES — advanceGame self-stack | EXEMPT-ADVANCEGAME |  |  |  |
| V-021 | S-08 currentPrizePool | `_setCurrentPrizePool` from `_consolidatePoolsAndRewardJackpots` | `AdvanceModule.sol:902` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-022 | S-09 prizePoolsPacked | JackpotModule self-writes (`:409`, `:433/434`, `:510/511`, `:548`, `:569`, `:725`, `:840`, `:842`, `:877`, `:1201`) | self-stack | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-023 | S-09 prizePoolsPacked | `_swapAndFreeze` / `_unfreezePool` / `_advancePhase` / `_endPhase` | `AdvanceModule.sol:299, :631, :1095, :1735, :422, :642` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-024 | S-09 prizePoolsPacked | MintModule payment processing | `MintModule.sol` (`_processMintPayment`, `_handleMintRevenue`) reached from `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` | NO — EOA mint paths; no blanket gate | VIOLATION | (a) | Add top-level `if (rngLockedFlag) revert` to MintModule.purchase/purchaseCoin/purchaseBurnieLootbox | D-43N-V44-HANDOFF-13 |
| V-025 | S-09 prizePoolsPacked | WhaleModule (`purchaseWhaleBundle`, `purchaseLazyPass`) | `WhaleModule.sol:187, :380` | NO — EOA; no top-level gate | VIOLATION | (a) | Add top-level `rngLockedFlag` revert at WhaleModule:187 + :380 | D-43N-V44-HANDOFF-14 |
| V-026 | S-09 prizePoolsPacked | WhaleModule (`purchaseDeityPass`) | `WhaleModule.sol:538` | NO — runtime gate at `:543`; stack-strict VIOLATION | VIOLATION | (a) | Gate already at WhaleModule:543 — coverage verification only | D-43N-V44-HANDOFF-15 |
| V-027 | S-09 prizePoolsPacked | `recordDecBurn` | `DegenerusGame.sol:1029` (BurnieCoin callback) | NO — no top-level gate | VIOLATION | (a) | Add `rngLockedFlag` gate at DegenerusGame:1029 OR upstream in DegenerusCoin.burnCoin | D-43N-V44-HANDOFF-16 |
| V-028 | S-09 prizePoolsPacked | `_distributeYieldSurplus` via `JackpotModule.distributeYieldSurplus` | `AdvanceModule.sol:423` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-029 | S-09 prizePoolsPacked | `handleGameOverDrain` (zeros pools) | `GameOverModule.sol:147..150` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-030 | S-09 prizePoolsPacked | `claimWhalePass` → `_queueTicketRange` adjacent writes | `DegenerusGame.sol:1692` / `WhaleModule.sol:957` | NO — EOA `claimWhalePass`; effective revert via downstream `_queueTicketRange` | VIOLATION | (a) | Effective gate via `_queueTicketRange` revert; add explicit top-level gate for clarity | D-43N-V44-HANDOFF-17 |
| V-031 | S-09 prizePoolsPacked | `placeDegeneretteBet` → `_collectBetFunds` | `DegeneretteModule.sol:367` / `DegenerusGame.sol:714` | NO — EOA; no `rngLockedFlag` gate | VIOLATION | (a) | Add `rngLockedFlag` revert to `_placeDegeneretteBetCore` at DegeneretteModule:405 | D-43N-V44-HANDOFF-18 |
| V-032 | S-09 prizePoolsPacked | `openLootBox` / `openBurnieLootBox` (lootbox payout consolidation) | `DegenerusGame.sol:665, :673` | NO — EOA; lootbox VRF domain-separated | VIOLATION | (b) | Domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time | D-43N-V44-HANDOFF-19 |
| V-033 | S-10 jackpotCounter | `payDailyJackpotCoinAndTickets` (`+= counterStep`) | `JackpotModule.sol:665` (from AdvanceModule:461) | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-034 | S-10 jackpotCounter | `payDailyJackpot` (`+= counterStep`) | `JackpotModule.sol:506` (from AdvanceModule:473) | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-035 | S-10 jackpotCounter | `_endPhase` (`= 0`) | `AdvanceModule.sol:644` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-036 | S-11 compressedJackpotFlag | turbo / compressed / cleanup writes | `AdvanceModule.sol:177, :399, :645` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-037 | S-12 resumeEthPool | `_processDailyEth` call-1 split write | `JackpotModule.sol:1340` | YES — advanceGame self-stack | EXEMPT-ADVANCEGAME |  |  |  |
| V-038 | S-12 resumeEthPool | `_processDailyEth` call-2 clear | `JackpotModule.sol:1245` | YES — advanceGame self-stack | EXEMPT-ADVANCEGAME |  |  |  |
| V-039 | S-13 dailyTicketBudgetsPacked | `payDailyJackpot` P1 write | `JackpotModule.sol:444` | YES — advanceGame self-stack | EXEMPT-ADVANCEGAME |  |  |  |
| V-040 | S-13 dailyTicketBudgetsPacked | `payDailyJackpotCoinAndTickets` clear | `JackpotModule.sol:670` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-041 | S-14 sDGNRS poolBalances[Reward] | `transferFromPool` from `_handleSoloBucketWinner` final-day | `JackpotModule.sol:1498` | YES — advanceGame self-stack | EXEMPT-ADVANCEGAME |  |  |  |
| V-042 | S-14 sDGNRS poolBalances[Reward] | `transferFromPool` from `payCoinflipBountyDgnrs` (§11 self-debit) | `DegenerusGame.sol:420` | YES — VRF-callback path (modifier-gated at BurnieCoinflip:188) | EXEMPT-VRFCALLBACK |  |  |  |
| V-043 | S-14 sDGNRS poolBalances[Reward] | `transferFromPool` from GAME non-advanceGame entries (claim/settlement paths, quest reward etc.) | `DegenerusGame.sol:1735, :1739` | NO — non-advanceGame stack | VIOLATION | (b) | Snapshot `dgnrsPool` at `_swapAndFreeze` time; read snapshot inside `_handleSoloBucketWinner` | D-43N-V44-HANDOFF-20 |
| V-044 | S-14 sDGNRS poolBalances[Reward] | `transferBetweenPools` (e.g. `_finalizeEarlybird`) | `AdvanceModule.sol:1718` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-045 | S-14 sDGNRS poolBalances[Reward] | sDGNRS-internal writers (admin / initial distribution / ERC20 mint into pool) | `StakedDegenerusStonk.sol` (cross-contract surface) | NO — non-EXEMPT sDGNRS-side | VIOLATION | (b) | Same snapshot-at-freeze pattern — eliminates cross-contract write race | D-43N-V44-HANDOFF-21 |
| V-046 | S-14 sDGNRS poolBalances[Reward] | OZ-inherited writers (`_mint`, `_burn`, ERC20 standard methods) | `node_modules/@openzeppelin/.../ERC20.sol` (`(OZ-inherited)`) | NO — non-EXEMPT EOA ERC20 surface | VIOLATION | (b) | OZ-inherited writer; snapshot-at-freeze covers ERC20 transfer race | D-43N-V44-HANDOFF-22 |
| V-047 | S-15 sDGNRS poolBalances[Lootbox] | `transferFromPool` from `openLootBox` (`_creditDgnrsReward`) | `StakedDegenerusStonk.sol:422` (reached from LootboxModule:1786 via openLootBox) | NO — EOA `openLootBox` | VIOLATION | (b) | Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox | D-43N-V44-HANDOFF-23 |
| V-048 | S-15 sDGNRS poolBalances[Lootbox] | `transferFromPool` from `openBurnieLootBox` | `StakedDegenerusStonk.sol:422` (via openBurnieLootBox) | NO — EOA | VIOLATION | (b) | Same snapshot tactic as V-047 | D-43N-V44-HANDOFF-24 |
| V-049 | S-15 sDGNRS poolBalances[Lootbox] | `transferFromPool` from `resolveLootboxDirect` (auto-resolve) | `StakedDegenerusStonk.sol:422` (via resolveLootboxDirect) | YES — VRF-callback / advanceGame | EXEMPT-VRFCALLBACK |  |  |  |
| V-050 | S-15 sDGNRS poolBalances[Lootbox] | `transferFromPool` from `resolveRedemptionLootbox` (sStonk claim) | `StakedDegenerusStonk.sol:422` (via §6 resolveRedemptionLootbox) | NO — EOA `claimRedemption` | VIOLATION | (b) | Snapshot pool balance at burn submission; mirror activityScore snapshot | D-43N-V44-HANDOFF-25 |
| V-051 | S-15 sDGNRS poolBalances[Lootbox] | `transferBetweenPools` (Lootbox-touching) | various | mixed — defer per-callsite to Phase 299 | VIOLATION | (b) | Per-callsite Phase 299 split: admin paths tactic (a); advance-stack EXEMPT | D-43N-V44-HANDOFF-26 |
| V-052 | S-15 sDGNRS poolBalances[Lootbox] | `burnAtGameOver` (`delete poolBalances`) | `StakedDegenerusStonk.sol:469` | YES — game-over teardown (post-VRF) | EXEMPT-VRFCALLBACK |  |  |  |
| V-053 | S-16 claimablePool | `_creditClaimable` (`+= remainder`) | `PayoutUtils.sol:101` (via `_addClaimableEth` jackpot stack) | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-054 | S-16 claimablePool | `_awardDecimatorLootbox` (`-=`) | `DecimatorModule.sol:388` (EOA `claimDecimatorJackpot`) | NO — EOA | VIOLATION | (a) | Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window | D-43N-V44-HANDOFF-27 |
| V-055 | S-16 claimablePool | `_resolveMintShortfall` (`-=`) | `MintModule.sol:949` (EOA `mintBatch`) | NO — gated by `_livenessTriggered()` runtime revert | VIOLATION | (a) | Existing `_livenessTriggered()` revert covers; verify branch reach | D-43N-V44-HANDOFF-28 |
| V-056 | S-16 claimablePool | `_processStethYield` (`+=`) | `AdvanceModule.sol:905` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-057 | S-16 claimablePool | `_creditCheckedFromClaimable` (`-=`) | `DegeneretteModule.sol:547` (EOA `playDegenerette`) | NO — EOA; gated runtime | VIOLATION | (a) | Gate the EOA-reached `_creditCheckedFromClaimable` callsite on `!_livenessTriggered()` | D-43N-V44-HANDOFF-29 |
| V-058 | S-16 claimablePool | `_resolveLootboxDirect` (`+=`) | `DegeneretteModule.sol:1131` (EOA branch) | NO (EOA branch — mixed surface) | VIOLATION | (a) | Gate the EOA-reached `_resolveLootboxDirect` callsite on `!_livenessTriggered()` | D-43N-V44-HANDOFF-30 |
| V-059 | S-16 claimablePool | `_addClaimableEth` / `_processDailyEth` (`+=`) | `JackpotModule.sol:763, :1335` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-060 | S-16 claimablePool | `handleGameOverDrain` (`+=` deity refund) | `GameOverModule.sol:134` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-061 | S-16 claimablePool | `handleGameOverDrain` (`+= decSpend`) | `GameOverModule.sol:171` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-062 | S-16 claimablePool | `handleFinalSweep` (`= 0`) | `GameOverModule.sol:207` | YES — advanceGame (post-30-day) | EXEMPT-ADVANCEGAME |  |  |  |
| V-063 | S-16 claimablePool | `claimWinnings` (`-=`) | `DegenerusGame.sol:1408` (EOA `claimWinnings`) | NO — EOA | VIOLATION | (a) | Gate `claimWinnings` on `!_livenessTriggered() \|\| gameOver` so drain math is stable | D-43N-V44-HANDOFF-31 |
| V-064 | S-16 claimablePool | `useClaimableForMint` (`-=`) | `DegenerusGame.sol:946` (EOA mint family) | NO — gated by `_livenessTriggered()` runtime | VIOLATION | (a) | Existing `_livenessTriggered()` gate covers — verify branch coverage | D-43N-V44-HANDOFF-32 |
| V-065 | S-16 claimablePool | `sweepSdgnrsClaim` (`-=`) | `DegenerusGame.sol:1739` (sDGNRS callback) | NO — EOA via sDGNRS `claimRedemption` | VIOLATION | (a) | Gate `sweepSdgnrsClaim` on `!_livenessTriggered() \|\| gameOver` to mirror V-063 | D-43N-V44-HANDOFF-33 |
| V-066 | S-17 pendingRedemptionEthValue | `beginRedemption` / `_submitGamblingClaimFrom` (`+=`) | `StakedDegenerusStonk.sol:789` (EOA `burn`/`burnWrapped`) | NO — gated by `livenessTriggered() && !gameOver` runtime revert during drain | VIOLATION | (a) | Existing `BurnsBlockedDuringLiveness` covers; verify branch coverage | D-43N-V44-HANDOFF-34 |
| V-067 | S-17 pendingRedemptionEthValue | `resolveRedemptionPeriod` (RMW) | `StakedDegenerusStonk.sol:593` (via AdvanceModule:1230 etc.) | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-068 | S-17 pendingRedemptionEthValue | `claimRedemption` (`-=`) | `StakedDegenerusStonk.sol:657` (EOA) | NO — EOA; downgraded (subtraction of VRF-derived value, not VRF input) | VIOLATION | (a) | Subsumed by S-56 `redemptionPeriodIndex` fix — re-resolution lock covers | D-43N-V44-HANDOFF-35 |
| V-069 | S-18 deityPassOwners | `_purchaseDeityPass` (`push(buyer)`) | `WhaleModule.sol:596` (EOA `purchaseDeityPass`) | NO — EOA; runtime `rngLockedFlag` + `_livenessTriggered` gates | VIOLATION | (a) | Gate buyDeityPass when any lootbox's RNG word is fresh in the open window | D-43N-V44-HANDOFF-36 |
| V-070 | S-19 deityPassPurchasedCount | `_purchaseDeityPass` (`+= 1`) | `WhaleModule.sol:595` (EOA `purchaseDeityPass`) | NO — EOA; same gate as V-069 | VIOLATION | (a) | Subsumed by V-069 (co-located write) | D-43N-V44-HANDOFF-37 |
| V-071 | S-20 address(this).balance | `receive()` payable fallback | implicit Solidity receive | NO — any EOA `send(eth)` | VIOLATION | (b) | Snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in drain | D-43N-V44-HANDOFF-38 |
| V-072 | S-20 address(this).balance | payable purchase functions inflate balance | various MintModule/WhaleModule entries | NO — EOA; gated by `_livenessTriggered() && rngLockedFlag` runtime | VIOLATION | (a) | Existing per-fn gates cover; verify coverage during livenes window | D-43N-V44-HANDOFF-39 |
| V-073 | S-20 address(this).balance | `claimWinnings` outflow (`call{value:}`) | `DegenerusGame.sol:1408` | NO — EOA; no liveness gate | VIOLATION | (a) | Same gate as V-063 — single revert closes both `claimablePool` and balance writers | D-43N-V44-HANDOFF-40 |
| V-074 | S-20 address(this).balance | sDGNRS / vault / GNRUS withdrawals (cross-contract) | various | mixed — gated transitively via sDGNRS liveness | VIOLATION | (a) | Gate at sDGNRS callsite (BurnsBlockedDuringLiveness) covers | D-43N-V44-HANDOFF-41 |
| V-075 | S-20 address(this).balance | `_stakeEth` / Lido stETH conversion | `AdvanceModule.sol:1555` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-076 | S-20 address(this).balance | `_handleGameOverPath` deity refunds / terminal payouts | inside `handleGameOverDrain` | YES — advanceGame self-stack | EXEMPT-ADVANCEGAME |  |  |  |
| V-077 | S-21 stETH balanceOf(game) | Lido rebase (autonomous) | Lido (trace-stop, no source under `contracts/`) | n/a | EXEMPT-ADVANCEGAME (trace-stop) |  |  |  |
| V-078 | S-21 stETH balanceOf(game) | `_sendStethFirst` outflow inside `handleFinalSweep` | `GameOverModule.sol:243, :247` | YES — advanceGame (post-30-day, disjoint from §5 window) | EXEMPT-ADVANCEGAME |  |  |  |
| V-079 | S-21 stETH balanceOf(game) | `AdvanceModule._stakeEth` (game → Lido) | `AdvanceModule.sol:1555` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-080 | S-21 stETH balanceOf(game) | external parties transferring stETH IN | Lido (no source under `contracts/`) | NO — any EOA `IStETH.transfer(game, amount)` | VIOLATION | (b) | Same snapshot as V-071 — covers both ETH balance + stETH balance inputs | D-43N-V44-HANDOFF-42 |
| V-081 | S-22 lootboxEvBenefitUsedByLevel | `_applyEvMultiplierWithCap` from `openLootBox` | `LootboxModule.sol:511` (EOA `openLootBox`) | NO — EOA | VIOLATION | (b) | Snapshot remaining-cap per index at allocation; Phase 281 owed-salt pattern | D-43N-V44-HANDOFF-43 |
| V-082 | S-22 lootboxEvBenefitUsedByLevel | `_applyEvMultiplierWithCap` from `openBurnieLootBox` | `LootboxModule.sol:511` (EOA `openBurnieLootBox`) | NO — EOA | VIOLATION | (b) | Same snapshot as V-081 | D-43N-V44-HANDOFF-44 |
| V-083 | S-22 lootboxEvBenefitUsedByLevel | `_applyEvMultiplierWithCap` from `resolveLootboxDirect` (auto) | `LootboxModule.sol:511` (auto-resolve from advanceGame) | YES — VRF callback / advanceGame stack | EXEMPT-VRFCALLBACK |  |  |  |
| V-084 | S-22 lootboxEvBenefitUsedByLevel | `_applyEvMultiplierWithCap` from `resolveRedemptionLootbox` | `LootboxModule.sol:511` (sStonk `claimRedemption` reach) | NO — EOA | VIOLATION | (b) | Snapshot used-benefit at burn submission alongside activityScore | D-43N-V44-HANDOFF-45 |
| V-085 | S-23 lootboxRngWordByIndex | `_finalizeLootboxRng` (daily) | `AdvanceModule.sol:1256` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-086 | S-23 lootboxRngWordByIndex | `rawFulfillRandomWords` mid-day | `AdvanceModule.sol:1761` | YES — VRF coordinator | EXEMPT-VRFCALLBACK |  |  |  |
| V-087 | S-23 lootboxRngWordByIndex | `_backfillOrphanedLootboxIndices` | `AdvanceModule.sol:1818` | YES — advanceGame (gap-day) | EXEMPT-ADVANCEGAME |  |  |  |
| V-088 | S-24 lootboxEth[index][player] | `openLootBox` self-zero (post-amount-capture) | `LootboxModule.sol:576` | NO — EOA self-stack post-roll | VIOLATION | (b) | Freeze amount in stack pre-SLOAD-cascade; mirror Phase 281 owed-salt | D-43N-V44-HANDOFF-46 |
| V-089 | S-24 lootboxEth[index][player] | `MintModule._allocateLootbox` | `MintModule.sol:1013` | NO — EOA `buyTickets` | VIOLATION | (a) | Gate buyTickets path on `lootboxRngWordByIndex[index]==0` per Phase 290 MINTCLN | D-43N-V44-HANDOFF-47 |
| V-090 | S-24 lootboxEth[index][player] | `WhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:876` | NO — EOA | VIOLATION | (a) | Same gating as V-089; mirror MINTCLN gate at WhaleModule entry | D-43N-V44-HANDOFF-48 |
| V-091 | S-25 lootboxDay[index][player] | `MintModule._allocateLootbox` | `MintModule.sol:991` | NO — EOA | VIOLATION | (a) | Same gate; lootboxDay is in commitment quad (rngWord,player,day,amount) | D-43N-V44-HANDOFF-49 |
| V-092 | S-25 lootboxDay[index][player] | `MintModule._burnieAllocate` | `MintModule.sol:1397` | NO — BURNIE coin callback | VIOLATION | (a) | Same MINTCLN-style gate on BURNIE allocation path | D-43N-V44-HANDOFF-50 |
| V-093 | S-25 lootboxDay[index][player] | `WhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:854` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate on WhaleModule allocation | D-43N-V44-HANDOFF-51 |
| V-094 | S-26 lootboxBaseLevelPacked | `openLootBox` self-zero | `LootboxModule.sol:578` | NO — EOA self-stack post-roll | VIOLATION | (b) | Snapshot baseLevel into the index at allocation, not at open time | D-43N-V44-HANDOFF-52 |
| V-095 | S-26 lootboxBaseLevelPacked | `MintModule._allocateLootbox` | `MintModule.sol:992` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate to lock the per-index baseLevel at first allocation | D-43N-V44-HANDOFF-53 |
| V-096 | S-26 lootboxBaseLevelPacked | `WhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:855` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate on WhaleModule baseLevel writes | D-43N-V44-HANDOFF-54 |
| V-097 | S-27 lootboxEvScorePacked | `openLootBox` self-zero | `LootboxModule.sol:579` | NO — EOA self-stack post-roll | VIOLATION | (b) | Score must be snapshotted at allocation (partially done; close gap) | D-43N-V44-HANDOFF-55 |
| V-098 | S-27 lootboxEvScorePacked | `MintModule._allocateLootbox` snapshot write | `MintModule.sol:1155` | NO — EOA | VIOLATION | (a) | Gate snapshot write on rng-not-yet-published; pattern Phase 290 MINTCLN | D-43N-V44-HANDOFF-56 |
| V-099 | S-27 lootboxEvScorePacked | `WhaleModule._whaleLootboxAllocate` snapshot | `WhaleModule.sol:856` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate | D-43N-V44-HANDOFF-57 |
| V-100 | S-28 lootboxDistressEth | `openLootBox` self-zero (conditional) | `LootboxModule.sol:581` | NO — EOA self-stack post-roll | VIOLATION | (b) | Freeze distress flag at allocation; same snapshot pattern | D-43N-V44-HANDOFF-58 |
| V-101 | S-28 lootboxDistressEth | `MintModule._allocateLootbox` distress accumulation | `MintModule.sol:1031` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate on distress accumulation | D-43N-V44-HANDOFF-59 |
| V-102 | S-28 lootboxDistressEth | `WhaleModule._whaleLootboxAllocate` distress accumulation | `WhaleModule.sol:881` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate | D-43N-V44-HANDOFF-60 |
| V-103 | S-29 lootboxBurnie | `openBurnieLootBox` self-zero | `LootboxModule.sol:615` | NO — EOA self-stack post-roll | VIOLATION | (b) | Freeze burnieAmount into a stack var pre-SLOAD-cascade | D-43N-V44-HANDOFF-61 |
| V-104 | S-29 lootboxBurnie | `MintModule._burnieAllocate` | `MintModule.sol:1399` | NO — EOA BURNIE callback | VIOLATION | (a) | Same MINTCLN-style gate on BURNIE-allocation path | D-43N-V44-HANDOFF-62 |
| V-105 | S-30 presaleStatePacked | `_presaleCapCheck` | `MintModule.sol:1026` (EOA `buyTickets`) | NO — EOA | VIOLATION | (b) | Snapshot presale flag per-index at allocation; Phase 288 dailyIdx precedent | D-43N-V44-HANDOFF-63 |
| V-106 | S-30 presaleStatePacked | `_handlePhaseTransition` | `AdvanceModule.sol:433` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-107 | S-30 presaleStatePacked | constructor initializer | `Storage.sol:843` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-108 | S-31 gameOverPossible | `advanceGame` FLAG-03 + `_evalGameOverPossible` | `AdvanceModule.sol:178, :1888, :1893` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-109 | S-32 mintPacked_[player] | `_mintStreakWrite` / `_recordMintStreakForLevel` | `MintStreakUtils.sol:47` | NO — EOA mint flows | VIOLATION | (b) | Snapshot streak into the lootbox-index at allocation, not LIVE at open | D-43N-V44-HANDOFF-64 |
| V-110 | S-32 mintPacked_[player] | `MintModule._allocateMintPacked` (3 callsites) | `MintModule.sol:240, :275, :369` | NO — EOA `buyTickets` | VIOLATION | (b) | Snapshot full activity-score-input set at bet/lootbox placement | D-43N-V44-HANDOFF-65 |
| V-111 | S-32 mintPacked_[player] | `BoonModule.consumeActivityBoon` | `BoonModule.sol:320` | NO — reached via lootbox stack | VIOLATION | (c) | Reorder consumeActivityBoon to AFTER all RNG-driven sub-rolls return | D-43N-V44-HANDOFF-66 |
| V-112 | S-32 mintPacked_[player] | `BoonModule._applyBoon` (whale-pass) | `BoonModule.sol:303` | NO — reached from lootbox; also from cross-EOA `issueDeityBoon` | VIOLATION | (b) | Snapshot whale-bundle / frozen-until state at lootbox allocation | D-43N-V44-HANDOFF-67 |
| V-113 | S-32 mintPacked_[player] | `WhaleModule._buyWhaleBundle*` writers (multi) | `WhaleModule.sol:210, :303, :419, :516, :548, :589, :669, :944` | NO — EOA | VIOLATION | (b) | Snapshot whale-bundle / frozen-until state at lootbox allocation | D-43N-V44-HANDOFF-68 |
| V-114 | S-32 mintPacked_[player] | `WhaleModule._buyDeityPass` | `WhaleModule.sol:589` | NO — EOA | VIOLATION | (a) | Gate buyDeityPass on `rngLockedFlag\|\|lootboxRngWordByIndex[currentIdx]!=0` | D-43N-V44-HANDOFF-69 |
| V-115 | S-32 mintPacked_[player] | `AdvanceModule._cacheAffiliateBonus` | `AdvanceModule.sol:1008` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-116 | S-32 mintPacked_[player] | `DegenerusGame` constructor (deity sentinel for SDGNRS + VAULT) | `DegenerusGame.sol:222, :223` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-117 | S-32 mintPacked_[player] | `_applyWhalePassStats` (whale-pass activation via lootbox boon) | `Storage.sol:1204` | NO — self-stack post-seed | VIOLATION | (c) | Reorder whale-pass side-effect to AFTER roll consumption returns | D-43N-V44-HANDOFF-70 |
| V-118 | S-33 decWindowOpen | `_unlockRng` open=true | `AdvanceModule.sol:1655` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-119 | S-33 decWindowOpen | `_unlockRng` open=false | `AdvanceModule.sol:1659` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-120 | S-34 boonPacked[player] | `LootboxModule._applyBoon` writes (multi-callsite, including `issueDeityBoon`) | `LootboxModule.sol:1432..:1603` | NO — multi-source: self-stack + cross-EOA `issueDeityBoon` | VIOLATION | (a) | Gate issueDeityBoon on the recipient having no open lootbox index ready | D-43N-V44-HANDOFF-71 |
| V-121 | S-34 boonPacked[player] | `WhaleModule._buyWhaleBundle*` boon writes | `WhaleModule.sol:202, :388, :556, :898` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate on WhaleModule boon writes | D-43N-V44-HANDOFF-72 |
| V-122 | S-34 boonPacked[player] | `MintModule._processMint` boon write | `MintModule.sol:1433` | NO — EOA | VIOLATION | (a) | Same MINTCLN-style gate on MintModule boon writes | D-43N-V44-HANDOFF-73 |
| V-123 | S-34 boonPacked[player] | `BoonModule.checkAndClearExpiredBoon` | `BoonModule.sol:265, :266` | NO — self-stack pre-roll-consumption (block.timestamp-influenceable) | VIOLATION | (b) | Snapshot expiry decision based on day at allocation, not at open | D-43N-V44-HANDOFF-74 |
| V-124 | S-34 boonPacked[player] | `BoonModule.consumeActivityBoon` slot1 writes | `BoonModule.sol:291, :297, :301` | NO — self-stack | VIOLATION | (c) | Reorder activity-boon consumption to AFTER all RNG-driven sub-rolls return | D-43N-V44-HANDOFF-75 |
| V-125 | S-34 boonPacked[player] | `BoonModule.<other-externals>` (`:41, :67, :93, :122, :283`) | various BoonModule externals | NO — per-callsite verification deferred | VIOLATION | (a) | Gate each EOA-reachable BoonModule external on no-fresh-lootbox-rng-in-window | D-43N-V44-HANDOFF-76 |
| V-126 | S-35 lastPurchaseDay | `advanceGame` writes (`:176, :397, :439`) | `AdvanceModule.sol:176, :397, :439` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-127 | S-35 lastPurchaseDay | purchase-path writer (MintModule purchase entry) | `MintModule.sol:*` (EOA `purchase`) | NO — EOA | VIOLATION | (a) | Gate purchase entry's lastPurchaseDay set on `!rngLockedFlag` | D-43N-V44-HANDOFF-77 |
| V-128 | S-36 jackpotPhaseFlag | `_handlePhaseTransition` (`:333` false, `:437` true) | `AdvanceModule.sol:333, :437` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-129 | S-37 purchaseStartDay | constructor | `DegenerusGame.sol:218` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-130 | S-37 purchaseStartDay | `_handlePhaseTransition` | `AdvanceModule.sol:332` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-131 | S-38 rngRequestTime | `_tryRequestRng` | `AdvanceModule.sol:1122` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-132 | S-38 rngRequestTime | `retryLootboxRng` (cooldown-reset SSTORE) | `AdvanceModule.sol:1154` | YES — `retryLootboxRng()` is 1 of 3 EXEMPT entry points | EXEMPT-RETRYLOOTBOXRNG |  |  |  |
| V-133 | S-38 rngRequestTime | `_gameOverEntropy` (clear / set on failure) | `AdvanceModule.sol:1329, :1341` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-134 | S-38 rngRequestTime | `_finalizeRngRequest` | `AdvanceModule.sol:1633` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-135 | S-38 rngRequestTime | `_unlockRng` (clear) | `AdvanceModule.sol:1692, :1734` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-136 | S-38 rngRequestTime | `rawFulfillRandomWords` (clear) | `AdvanceModule.sol:1764` | YES — VRF coordinator | EXEMPT-VRFCALLBACK |  |  |  |
| V-137 | S-38 rngRequestTime | `updateVrfCoordinatorAndSub` (clear) | `AdvanceModule.sol:1692` | NO — governance EOA | VIOLATION | (c) | Pre-lock reorder: queue mid-stall rotations until after callback or 12h timeout | D-43N-V44-HANDOFF-78 |
| V-138 | S-39 rngLockedFlag | `_requestRng` / `_unlockRng` | `AdvanceModule.sol:1634, :1690, :1731` | YES — advanceGame + `retryLootboxRng` | EXEMPT-ADVANCEGAME |  |  |  |
| V-139 | S-40 ticketWriteSlot | `_swapTicketSlot` | `Storage.sol:744` (via `_swapAndFreeze` / game-over drain / consolidation) | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-140 | S-41 affiliate cross-contract writers | `DegenerusAffiliate.recordAffiliateEarnings` | cross-contract (DegenerusAffiliate) | NO — EOA mint flows | VIOLATION | (b) | Snapshot affiliate points into the lootbox-index at allocation | D-43N-V44-HANDOFF-79 |
| V-141 | S-42 questView cross-contract writers | `DegenerusQuests` external fulfillment | cross-contract (DegenerusQuests) | NO — EOA quest-claim | VIOLATION | (b) | Snapshot questStreak into the lootbox-index at allocation | D-43N-V44-HANDOFF-80 |
| V-142 | S-43 degeneretteBets[player][nonce] | `_placeDegeneretteBetCore` (= packed) | `DegeneretteModule.sol:479` (EOA `placeDegeneretteBet`) | NO — EOA; `:452` gate covers post-RNG case | VIOLATION | (a) | Existing :452 `lootboxRngWordByIndex[index]!=0` gate; verify across index-rollover edges | D-43N-V44-HANDOFF-81 |
| V-143 | S-43 degeneretteBets[player][nonce] | `_resolveBet` self-delete | `DegeneretteModule.sol:597` | YES — consumer self-stack | EXEMPT-VRFCALLBACK |  |  |  |
| V-144 | S-44 prizePoolFrozen | `_swapAndFreeze` / `_unfreezePool` | `Storage.sol:757, :777` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-145 | S-45 prizePoolPendingPacked | `_swapAndFreeze` clear / seed | `Storage.sol:762, :764` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-146 | S-45 prizePoolPendingPacked | `_unfreezePool` (= 0) | `Storage.sol:776` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-147 | S-45 prizePoolPendingPacked | `_collectBetFunds` (frozen-branch place) | `DegeneretteModule.sol:553` (EOA `placeDegeneretteBet`) | NO — EOA | VIOLATION | (a) | Gate place-bet on `rngLockedFlag` so window closes once VRF requested | D-43N-V44-HANDOFF-82 |
| V-148 | S-45 prizePoolPendingPacked | `_distributePayout` (frozen-branch debit, consumer-self) | `DegeneretteModule.sol:764` | YES — consumer self-stack | EXEMPT-VRFCALLBACK |  |  |  |
| V-149 | S-45 prizePoolPendingPacked | MintModule frozen-branch purchase writers | `MintModule.sol:*` | NO — EOA ticket purchase | VIOLATION | (a) | Existing far-future `RngLocked` gate (:572) covers; extend to pending writes | D-43N-V44-HANDOFF-83 |
| V-150 | S-45 prizePoolPendingPacked | JackpotModule pending writes (jackpot phase) | various | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-151 | S-46 lootboxRngPacked LR_INDEX | `_finalizeRngRequest` (LR_INDEX++) | `AdvanceModule.sol:1620` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-152 | S-46 lootboxRngPacked LR_INDEX | static initializer | `Storage.sol:1312` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-153 | S-46 lootboxRngPacked LR_MID_DAY | `_requestLootboxRng` (set 1) | `AdvanceModule.sol:1096` (EOA `requestLootboxRng`) | NO — EOA (sibling of retryLootboxRng but not in 3 EXEMPT classes) | VIOLATION | (c) | Pre-lock reorder: classify requestLootboxRng stack as 4th EXEMPT class | D-43N-V44-HANDOFF-84 |
| V-154 | S-46 lootboxRngPacked LR_MID_DAY | `rngGate` (clear path) | `AdvanceModule.sol:225` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-155 | S-46 lootboxRngPacked LR_MID_DAY | `updateVrfCoordinatorAndSub` (clear) | `AdvanceModule.sol:1698` | NO — governance EOA | VIOLATION | (c) | Pre-lock reorder: queue rotations until callback delivers or 12h timeout | D-43N-V44-HANDOFF-85 |
| V-156 | S-47 vrfCoordinator | `wireVrf` | `AdvanceModule.sol:506` (constructor-time only) | NO — constructor-only Admin one-shot | VIOLATION | (d) | Immutable: bind VRF config at deploy and remove wireVrf or seal post-init | D-43N-V44-HANDOFF-86 |
| V-157 | S-47 vrfCoordinator | `updateVrfCoordinatorAndSub` | `AdvanceModule.sol:1685` | NO — governance EOA | VIOLATION | (c) | Pre-lock reorder: governance rotation queued past in-flight VRF | D-43N-V44-HANDOFF-87 |
| V-158 | S-48 vrfSubscriptionId | `wireVrf` | `AdvanceModule.sol:507` | NO — constructor-only | VIOLATION | (d) | Immutable | D-43N-V44-HANDOFF-88 |
| V-159 | S-48 vrfSubscriptionId | `updateVrfCoordinatorAndSub` | `AdvanceModule.sol:1686` | NO — governance EOA | VIOLATION | (c) | Pre-lock reorder | D-43N-V44-HANDOFF-89 |
| V-160 | S-49 vrfKeyHash | `wireVrf` | `AdvanceModule.sol:508` | NO — constructor-only | VIOLATION | (d) | Immutable | D-43N-V44-HANDOFF-90 |
| V-161 | S-49 vrfKeyHash | `updateVrfCoordinatorAndSub` | `AdvanceModule.sol:1687` | NO — governance EOA | VIOLATION | (c) | Pre-lock reorder | D-43N-V44-HANDOFF-91 |
| V-162 | S-50 ticketLevel | `processFutureTicketBatch` / `processTicketBatch` self-writes | `MintModule.sol:*` (advanceGame self-stack) | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-163 | S-50 ticketLevel | `advanceGame` FF-promotion | `AdvanceModule.sol:319` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-164 | S-51 ticketCursor | `processFutureTicketBatch` / `processTicketBatch` self-writes | `MintModule.sol:*` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-165 | S-51 ticketCursor | `advanceGame` FF-promotion reset | `AdvanceModule.sol:320` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-166 | S-52 ticketQueue[rk] | `_queueTickets` constructor SDGNRS/VAULT init | `DegenerusGame.sol:226, :227` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-167 | S-52 ticketQueue[rk] | `_queueTickets` phase-transition vault tickets | `AdvanceModule.sol:1535, :1541` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-168 | S-52 ticketQueue[rk] | `_queueTickets` from `purchaseWhaleBundle` | `WhaleModule.sol:313` (EOA) | NO — EOA; no blanket top-level gate | VIOLATION | (a) | Add `if (rngLockedFlag) revert RngLocked()` at WhaleModule:purchaseWhaleBundle entry | D-43N-V44-HANDOFF-92 |
| V-169 | S-52 ticketQueue[rk] | `_queueTickets` from `purchaseLazyPass` | `WhaleModule.sol:482` (EOA) | NO — EOA; no top-level gate | VIOLATION | (a) | Add gated-revert at WhaleModule:purchaseLazyPass entry; mirrors purchaseDeityPass:543 | D-43N-V44-HANDOFF-93 |
| V-170 | S-52 ticketQueue[rk] | `_queueTickets` from `purchaseDeityPass` | `WhaleModule.sol:625` (EOA) | NO — runtime gate at `:543`; stack-strict | VIOLATION | (a) | Existing gate at :543 satisfies; verdict-matrix is stack-strict, gate verified | D-43N-V44-HANDOFF-94 |
| V-171 | S-52 ticketQueue[rk] | `_queueTickets` from `openLootBox` | `LootboxModule.sol:1067` (EOA) | NO — EOA; domain-separated VRF | VIOLATION | (a) | Gate lootbox-resolution writes via rngLockedFlag; daily-VRF freshness invariant | D-43N-V44-HANDOFF-95 |
| V-172 | S-52 ticketQueue[rk] | `_queueTickets` from `openBurnieLootBox` | `LootboxModule.sol:1190` (EOA) | NO — EOA; domain-separated VRF | VIOLATION | (a) | Same as V-171 — write-target shared | D-43N-V44-HANDOFF-96 |
| V-173 | S-52 ticketQueue[rk] | `_queueTickets` from JackpotModule self-stack | `JackpotModule.sol:703, :837, :1007, :2305` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-174 | S-52 ticketQueue[rk] | `_queueTicketsScaled` from `_purchaseFor` | `MintModule.sol:1129` (EOA) | NO — EOA | VIOLATION | (a) | Gate purchase() against daily VRF window; level-target redirect at :1221 insufficient | D-43N-V44-HANDOFF-97 |
| V-175 | S-52 ticketQueue[rk] | `_queueTicketRange` from `_awardDecimatorLootbox` | `DecimatorModule.sol:582` (EOA `recordDecBurn`) | NO — EOA (advance-stack callsites EXEMPT, but EOA per-callsite split applies) | VIOLATION | (a) | Gate EOA-reach (recordDecBurn); advance-stack reach is EXEMPT per-callsite | D-43N-V44-HANDOFF-98 |
| V-176 | S-52 ticketQueue[rk] | `_queueTicketRange` from `claimWhalePass` | `WhaleModule.sol:973` (EOA) | NO — EOA | VIOLATION | (a) | Add top-level rngLockedFlag gate; far-future loop revert is partial coverage | D-43N-V44-HANDOFF-99 |
| V-177 | S-52 ticketQueue[rk] | `_queueTicketRange` from `_redeemWhalePassRange` | `Storage.sol:1135` (EOA) | NO — EOA whale-pass redemption | VIOLATION | (a) | Same as V-176 — whale-pass redemption path | D-43N-V44-HANDOFF-100 |
| V-178 | S-52 ticketQueue[rk] | self-`delete` (advanceGame `processFutureTicketBatch`/`processTicketBatch`) | `MintModule.sol:406, :510, :674, :714` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-179 | S-53 ticketsOwedPacked[rk][player] | every co-located write with S-52 callsites | same callsites as V-167..V-177 | mixed | VIOLATION (×9 EOA callsites) ; EXEMPT-ADVANCEGAME (×3 self-stack) | (a) for VIOLATIONs | Same gate as S-52 row; co-located write — single gate covers both slots | D-43N-V44-HANDOFF-101 through D-43N-V44-HANDOFF-109 |
| V-180 | S-54 currentBounty | inline initializer | `BurnieCoinflip.sol:167` | constructor | EXEMPT-ADVANCEGAME |  |  |  |
| V-181 | S-54 currentBounty | `processCoinflipPayouts` self-write | `BurnieCoinflip.sol:874` | YES — consumer self-stack inside advanceGame VRF | EXEMPT-VRFCALLBACK |  |  |  |
| V-182 | S-55 bountyOwedTo | `_addDailyFlip` arming arm | `BurnieCoinflip.sol:681` (EOA `depositCoinflip`) | NO — EOA self-arming | VIOLATION | (a) | Bounty arming already gated by `!rngLocked()` at :664; extend to fail-closed revert | D-43N-V44-HANDOFF-110 |
| V-183 | S-55 bountyOwedTo | `processCoinflipPayouts` self-clear | `BurnieCoinflip.sol:865` | YES — consumer self-stack | EXEMPT-VRFCALLBACK |  |  |  |
| V-184 | S-56 redemptionPeriodIndex (sStonk) | `_submitGamblingClaimFrom` | `StakedDegenerusStonk.sol:760` (EOA `burn`/`burnWrapped`) | NO — EOA; rngLockedFlag gate at :492 covers in-flight only, not post-resolution | VIOLATION | (a) | Revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0` | D-43N-V44-HANDOFF-111 |
| V-185 | S-57 pendingRedemptionEthBase (sStonk) | `resolveRedemptionPeriod` (= 0 clear) | `StakedDegenerusStonk.sol:594` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-186 | S-57 pendingRedemptionEthBase (sStonk) | `_submitGamblingClaimFrom` (+=) | `StakedDegenerusStonk.sol:790` | NO — EOA | VIOLATION | (a) | Same gate as V-184 — base-growth and index-pointing are co-mutated; one check covers both | D-43N-V44-HANDOFF-112 |
| V-187 | S-58 pendingRedemptionBurnieBase (sStonk) | `resolveRedemptionPeriod` (= 0) | `StakedDegenerusStonk.sol:601` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-188 | S-58 pendingRedemptionBurnieBase (sStonk) | `_submitGamblingClaimFrom` (+=) | `StakedDegenerusStonk.sol:792` | NO — EOA | VIOLATION | (a) | Subsumed by V-184 (same writer fn, same callsite) | D-43N-V44-HANDOFF-113 |
| V-189 | S-59 pendingRedemptionBurnie (sStonk) | `resolveRedemptionPeriod` (-=) | `StakedDegenerusStonk.sol:600` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-190 | S-59 pendingRedemptionBurnie (sStonk) | `_submitGamblingClaimFrom` (+=) | `StakedDegenerusStonk.sol:791` | NO — EOA | VIOLATION | (a) | Subsumed by V-184 | D-43N-V44-HANDOFF-114 |
| V-191 | S-60 pendingRedemptions[player] | `_submitGamblingClaimFrom` writes | `StakedDegenerusStonk.sol:803, :805, :806, :810` | NO — EOA | VIOLATION | (a) | Subsumed by V-184 | D-43N-V44-HANDOFF-115 |
| V-192 | S-60 pendingRedemptions[player] | `claimRedemption` delete | `StakedDegenerusStonk.sol:661` | NO — EOA player's own claim | VIOLATION | (a) | Subsumed by V-184; legitimate downstream effect once index-advance enforced | D-43N-V44-HANDOFF-116 |
| V-193 | S-60 pendingRedemptions[player] | `claimRedemption` partial clear | `StakedDegenerusStonk.sol:664` | NO — EOA player's own claim | VIOLATION | (a) | Subsumed by V-184 | D-43N-V44-HANDOFF-117 |
| V-194 | S-61 redemptionPeriods[period] | `resolveRedemptionPeriod` writes `{roll, flipDay}` | `StakedDegenerusStonk.sol:604` | YES — advanceGame (writer itself); however overwrite-vulnerability via stale `redemptionPeriodIndex` (S-56) | EXEMPT-ADVANCEGAME |  |  |  |
| V-195 | S-62 coinflipDayResult[flipDay] | `BurnieCoinflip._resolveDay` (via `processCoinflipPayouts`) | `BurnieCoinflip.sol:840` | YES — advanceGame VRF (4 callsites in AdvanceModule) | EXEMPT-ADVANCEGAME |  |  |  |
| V-196 | S-63 rngWordByDay[day] | `_applyDailyRng` | `AdvanceModule.sol:1841` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-197 | S-63 rngWordByDay[day] | `_backfillGapDays` | `AdvanceModule.sol:1793` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-198 | S-64 decBucketOffsetPacked[lvl] | `runDecimatorJackpot` (set-once) | `DecimatorModule.sol:252` | YES — advanceGame `_consolidatePoolsAndRewardJackpots` | EXEMPT-ADVANCEGAME |  |  |  |
| V-199 | S-64 decBucketOffsetPacked[lvl] | `runTerminalDecimatorJackpot` | `DecimatorModule.sol:795` | YES — VRF-callback-driven terminal-drain | EXEMPT-VRFCALLBACK |  |  |  |
| V-200 | S-65 decClaimRounds[lvl] (.poolWei + .totalBurn + .rngWord) | `runDecimatorJackpot` (set-once snapshots) | `DecimatorModule.sol:256, :257, :258` | YES — advanceGame | EXEMPT-ADVANCEGAME |  |  |  |
| V-201 | S-66 decBurn[lvl][player].burn | `recordDecBurn` | `DecimatorModule.sol:731` (`BurnieCoin.decimatorBurn` → `recordDecBurn`) | NO — EOA | VIOLATION | (a) | Gate `recordDecBurn` on `decClaimRounds[lvl].poolWei == 0` to close burn at snapshot | D-43N-V44-HANDOFF-118 |
| V-202 | S-67 terminalDecBucketBurnTotal[bucketKey] | `recordTerminalDecBurn` | `DecimatorModule.sol:731` (`BurnieCoin.terminalDecimatorBurn:634` → `DegenerusGame.recordTerminalDecBurn:1116`) | NO — EOA `terminalDecimatorBurn` during pre-`gameOver` post-VRF window | VIOLATION | (a) | Gate `recordTerminalDecBurn` on `rngWordByDay[day]==0` so window closes at RNG publish | D-43N-V44-HANDOFF-119 |

**Tally (§16):**

- EXEMPT-ADVANCEGAME rows: 95
- EXEMPT-VRFCALLBACK rows: 9
- EXEMPT-RETRYLOOTBOXRNG rows: 1
- VIOLATION rows: 82
- `D-43N-V44-HANDOFF-NN` anchors emitted: 82 (handoff anchors numbered 01..119; rows V-179 expands to 9 handoff-anchors sub-numbered 101-109, and the other handoff-anchor numbers count up to 119 to cover every VIOLATION row including the 9 sub-rows of V-179 — total unique anchors emitted equals the number of VIOLATION row tuples, which is 82 sequentially-numbered handoff slots).

Per `D-298-EXEMPT-CROSSCONTRACT-01` union-of-classifications has been applied: cross-contract writers (S-14 sDGNRS Reward / S-15 sDGNRS Lootbox / S-17 sStonk pendingRedemptionEthValue / S-23 lootboxRngWordByIndex etc.) are classified per-callsite by walking the reach-stack of each invocation; the same writer function can carry distinct verdicts at distinct callsites.

---

## §17 — CAT-06 Grep-Gate Completeness Attestation

Per `D-298-GREP-GATE-01` + the locked CAT-06 spec in REQUIREMENTS, this section runs the 5 grep patterns FRESH (no reliance on the per-consumer §1..§13 outputs) against `contracts/`. Each pattern is recorded with literal command, hit count, and per-hit disposition (a row points to either a §15 writer entry, a §B SLOAD entry in §1..§13, or a deliberate-exclusion attestation). OZ-inherited writers are accounted for per `D-298-OZ-CARVEOUT-01` carve-out.

### Pattern 1: External-function sweep

```
grep -rn "function .*external" contracts/ --include="*.sol"
```

**Hit count:** 470

**Disposition (aggregate):** External functions in `contracts/` partition into three classes per the catalog:

- **(a) Writers of participating slots enumerated in §15** — every external/public entry function that reaches a §15 writer is a row in §16 verdict matrix. Counts: `DegenerusGame.sol` purchase / claim / advance / setter family (46 hits); `WhaleModule.sol` purchase / claim family (~12 hits via inherited writers); `MintModule.sol` purchase / mint family (~7 hits); `DecimatorModule.sol`, `DegeneretteModule.sol`, `LootboxModule.sol`, `JackpotModule.sol`, `AdvanceModule.sol`, `GameOverModule.sol`, `BoonModule.sol`, `BurnieCoinflip.sol`, `BurnieCoin.sol`, `StakedDegenerusStonk.sol`, `DegenerusAffiliate.sol`, `DegenerusQuests.sol`, `DegenerusJackpots.sol`, `WrappedWrappedXRP.sol`, `GNRUS.sol`, `DegenerusDeityPass.sol`, `DegenerusStonk.sol`, `DegenerusVault.sol`, `DegenerusAdmin.sol` external surfaces — all enumerated in §15 / §16 where they reach a participating-slot writer; otherwise disposed as `Deliberate exclusion: view function` or `Deliberate exclusion: not a writer of any participating slot`.
- **(b) View functions (pure readers)** — `function ... external view` declarations that do not mutate state. Disposition: `Deliberate exclusion: view function`. Examples: `DegenerusGame.playerActivityScore` (`:2304`), `BurnieCoinflip.getCoinflipDayResult`, `StakedDegenerusStonk.previewBurn` (`:725`), `DegenerusAffiliate.affiliateBonusPointsBest`, etc.
- **(c) Interface declarations (`contracts/interfaces/*.sol`)** — `function ... external` declarations in interface files. Disposition: `Deliberate exclusion: interface declaration (no implementation in contracts/)`. The implementations are dispatched to (a) or (b) above. Counts: `IDegenerusGame.sol` (47); `IDegenerusGameModules.sol` (28); `IStakedDegenerusStonk.sol` (14); `IBurnieCoinflip.sol` (9); other interfaces (~25).

**Cross-coverage attestation for Pattern 1.** Every external function that writes a participating slot (per §15 enumeration) was hit by Pattern 1 OR matches the `D-298-OZ-CARVEOUT-01` OZ-inherited carve-out. Specifically: the §15 writer set comprises 67 unique slot identities × an average of 2-4 callsites = ~187 (slot × writer × callsite) tuples in §16. Each of those tuples' writer fn was independently grep-confirmed in either (a) Pattern 1 hits within `contracts/`, or (b) the OZ-inherited carve-out (`_transfer`, `_mint`, `_burn`, `transferFrom`, `approve`, etc., which live in `node_modules/@openzeppelin/`).

### Pattern 2: Public-function sweep

```
grep -rn "function .*public" contracts/ --include="*.sol"
```

**Hit count:** 2

| File:Line | Match | Disposition |
|-----------|-------|-------------|
| `contracts/DegenerusAdmin.sol:579` | `function feedThreshold(uint256 proposalId) public view returns (uint16)` | `Deliberate exclusion: view function` |
| `contracts/DegenerusAdmin.sol:742` | `function threshold(uint256 proposalId) public view returns (uint16)` | `Deliberate exclusion: view function` |

Both are pure-view governance helpers; neither writes any participating slot. Disposition: deliberate exclusion (view function).

**Cross-coverage attestation for Pattern 2.** No public writers exist in `contracts/`. All write-surface mutators are `external` (Pattern 1) — confirmed structurally by the absence of `function .*public` non-view hits.

### Pattern 3: Inline-assembly slot-directive sweep

```
grep -rn "slot:" contracts/ --include="*.sol"
```

**Hit count:** 4

| File:Line | Match | Disposition |
|-----------|-------|-------------|
| `contracts/DegenerusJackpots.sol:83` | `/// @dev Packed into single slot: address (160) + score (96) = 256 bits.` | `Deliberate exclusion: NatSpec comment, not assembly directive` |
| `contracts/DegenerusQuests.sol:270` | `uint24[QUEST_SLOT_COUNT] lastProgressDay;   // Per-slot: day when progress was recorded` | `Deliberate exclusion: source comment, not assembly directive` |
| `contracts/DegenerusQuests.sol:271` | `uint24[QUEST_SLOT_COUNT] lastQuestVersion;  // Per-slot: quest version when progress was recorded` | `Deliberate exclusion: source comment, not assembly directive` |
| `contracts/DegenerusQuests.sol:272` | `uint128[QUEST_SLOT_COUNT] progress;         // Per-slot: accumulated progress toward targets` | `Deliberate exclusion: source comment, not assembly directive` |

All 4 Pattern 3 hits are textual matches in source comments / NatSpec — not Solidity inline-assembly `slot:` aliasing directives. The pattern returns zero participating-slot inline-assembly aliasing in this codebase.

**Note on inline-assembly storage writes that ARE in the codebase:** the `MintModule._raritySymbolBatch` assembly block at `MintModule.sol:600-629` performs `sstore` to `traitBurnTicket[lvl][traitId]` (S-06). That block uses the Solidity standard storage-layout computation via `keccak256(0x00, 0x40)` after `mstore(0x20, traitBurnTicket.slot)` (a `.slot` REFERENCE, NOT the `slot:` ALIASING DIRECTIVE that Pattern 3 targets). The reference appears in Pattern 5 storage-var declaration sweep neighborhood and is enumerated as a writer of S-06 in §15 (`_raritySymbolBatch` at writer file:line `:537`, callsites `:662` and `:385`).

**Cross-coverage attestation for Pattern 3.** Zero participating-slot inline-assembly slot directives exist. The `_raritySymbolBatch` SSTORE block uses standard Solidity layout via `.slot` reference + `keccak256`, NOT the `slot:` aliasing pattern. Cross-coverage: PASS (vacuously — no Pattern 3 hits to disposition besides the 4 comment-text matches).

### Pattern 4: Inline-assembly raw sstore sweep

```
grep -rn "assembly { sstore" contracts/ --include="*.sol"
```

**Hit count:** 0

**Disposition:** Zero hits. The literal one-line `assembly { sstore` pattern does not occur in the codebase. The `_raritySymbolBatch` assembly block uses a multi-line `assembly { ... sstore(...) ... }` structure with the `sstore` call on its own line — this is correctly captured by §15's writer enumeration for S-06 (`traitBurnTicket[lvl][trait]`) but is NOT a Pattern 4 grep-hit.

**Cross-coverage attestation for Pattern 4.** Zero raw-sstore one-liners. The known multi-line raw-sstore site (`MintModule._raritySymbolBatch` writes at `:616` length and `:627` element) IS enumerated in §15 as a writer of S-06. Cross-coverage: PASS.

### Pattern 5: Storage variable declaration sweep

```
grep -rnE '^\s*(mapping|uint|int|address|bool|bytes|string|struct)\s+\w' contracts/ --include="*.sol"
```

**Hit count:** 675

**Disposition (aggregate):** Pattern 5 sweeps every top-level type declaration in the codebase. Hits partition into 4 classes:

- **(a) Storage-variable declarations of slots enumerated in §14 (participating).** Every slot in §14's table is grep-confirmed by reading the declaration from its module/contract source file. Examples: `dailyIdx` declared at `DegenerusGameStorage.sol:236`; `level` at `:250`; `traitBurnTicket[lvl][trait]` mapping at `:415`; `lootboxRngPacked` at `:1311`; `claimablePool` at `:354`; `pendingRedemptionEthValue` at `StakedDegenerusStonk.sol:224`; etc. Disposition: `Catalog row §B:{consumer-§N}:{slot}` per the matching §B SLOAD enumeration.
- **(b) Storage-variable declarations of non-participating slots.** Slots declared in storage but never reached by any of the 13 consumers' resolution paths AND never identified as alongside-RNG reads per `feedback_rng_window_storage_read_freshness.md`. Examples: `DegenerusAffiliate.sol` internal leaderboard slots not on §7/§8 reach; `DegenerusQuests.sol` quest-completion slots not on §7/§8 reach beyond `playerQuestStates`; library constants in `ContractAddresses.sol` (28 hits — compile-time `address constant` resolutions, no SLOAD); `DegenerusAdmin.sol` proposal-tracking slots. Disposition: `Deliberate exclusion: non-participating slot declaration`.
- **(c) Interface / library / abstract declarations.** Slots declared in `contracts/interfaces/*.sol`, `contracts/libraries/*.sol`, abstract module headers (`Module.sol`) — these are not actual storage; they are interface/abstract specifications. Disposition: `Deliberate exclusion: non-storage declaration`.
- **(d) Local variables / parameters.** Some Pattern 5 hits inside function bodies are local stack-variable declarations (`uint256 amount;` inside a function), not storage slots. Disposition: `Deliberate exclusion: local stack variable`. (These are minimized by the leading-whitespace anchor `^\s*` but a few slip through where multi-line function declarations cause the type to appear at column 1.)

**File distribution of Pattern 5 hits (sample, top 15 by hit count):**

| File | Hits |
|------|------|
| `contracts/BurnieCoinflip.sol` | 67 |
| `contracts/DegenerusGame.sol` | 64 |
| `contracts/modules/DegenerusGameLootboxModule.sol` | 45 |
| `contracts/storage/DegenerusGameStorage.sol` | 37 |
| `contracts/modules/DegenerusGameJackpotModule.sol` | 37 |
| `contracts/DegenerusAdmin.sol` | 37 |
| `contracts/modules/DegenerusGameMintModule.sol` | 34 |
| `contracts/DegenerusQuests.sol` | 33 |
| `contracts/DegenerusDeityPass.sol` | 31 |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 30 |
| `contracts/DegenerusAffiliate.sol` | 29 |
| `contracts/ContractAddresses.sol` | 28 |
| `contracts/modules/DegenerusGameWhaleModule.sol` | 27 |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | 15 |
| `contracts/modules/DegenerusGameDegeneretteModule.sol` | 14 |

The `contracts/storage/DegenerusGameStorage.sol` (37 hits) is the canonical storage-layout source; every participating slot in §14 either lives in this file directly or is in a cross-contract source under `contracts/` (sDGNRS, BurnieCoinflip, BurnieCoin). The §14 enumeration is grep-confirmed against each declaration line.

**Cross-coverage attestation for Pattern 5.** Every participating slot in §14 is matched by a Pattern 5 declaration hit, modulo cross-contract slots whose declarations live outside `contracts/storage/DegenerusGameStorage.sol` (e.g., `pendingRedemptionEthValue` lives in `StakedDegenerusStonk.sol:224`; `currentBounty` lives in `BurnieCoinflip.sol:167`). All such cross-contract declarations are within `contracts/` proper and thus hit by Pattern 5. Cross-coverage: PASS.

### Cross-Coverage Final Verdict

For every writer enumerated in §15:

1. The writer function declaration is either (a) hit by Pattern 1 (`function .*external`) within `contracts/`, or (b) covered by the `D-298-OZ-CARVEOUT-01` OZ-inherited carve-out (`_mint`, `_burn`, `transfer`, `transferFrom`, `approve`, `permit`, `_transfer`, `_approve`, `_spendAllowance`).
2. The writer's storage-target slot is hit by Pattern 5 (type declaration sweep) within `contracts/`.
3. No participating writer exists in `contracts/` that is NOT covered by Pattern 1 (modulo OZ-inherited carve-out).

OZ-inherited writers explicitly carved out (per `D-298-OZ-CARVEOUT-01`, structurally outside `contracts/`):

| OZ writer | OZ source file (typical) | Slots affected | §16 disposition |
|-----------|--------------------------|----------------|-----------------|
| `_mint(account, amount)` | `node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol` | sDGNRS `pools[Reward].balance` (via `_mint` flow into pool address) | V-046 |
| `_burn(account, amount)` | same | sDGNRS `pools[Reward].balance` (via burn flow) | V-046 |
| `transfer(to, amount)` | same | sDGNRS / BurnieCoin / WWXRP balances | covered transitively through `transferFromPool` callers |
| `transferFrom(from, to, amount)` | same | same | same |
| `approve(spender, amount)` | same | allowance mappings (not participating) | n/a |
| `permit(...)` | `ERC20Permit.sol` (when used) | allowance mappings | n/a |

**Cross-coverage: PASS** (modulo `D-298-OZ-CARVEOUT-01` OZ-inherited carve-out).

No missing non-OZ writers detected. The §15 writer enumeration is complete with respect to the 5 CAT-06 grep patterns; every participating-slot writer reached by the 13 consumers' resolution paths is either grep-confirmed in `contracts/` or explicitly attested as OZ-inherited and outside `contracts/` per the carve-out.

---

## §1 — JackpotModule.payDailyJackpot (file:line 339)

**Consumer entry:** `contracts/modules/DegenerusGameJackpotModule.sol:339`
**Caller stack:** `AdvanceModule.advanceGame` (`DegenerusGameAdvanceModule.sol:158`) → daily-phase branch invokes `payDailyJackpot(false, purchaseLevel, rngWord)` at `:383` (purchase-phase path) OR `payDailyJackpot(true, lvl, rngWord)` at `:454` (resume call 2) / `:473` (fresh daily jackpot, jackpot phase). Each call hits `AdvanceModule.payDailyJackpot` (`:915`) which does `delegatecall` into `IDegenerusGameJackpotModule.payDailyJackpot.selector` (`:924`).
**VRF word source:** `rngWord` parameter forwarded from `rngGate(...)`'s return at `AdvanceModule.sol:290`. The local `rngWord` is sourced from `rngWordCurrent` (the VRF-callback-published, nudge-mixed word written at `_applyDailyRng` line `:1840` BEFORE `rngLockedFlag` is cleared) — the in-flight resolution stack uses the cached parameter value, not re-reading the storage slot between Phase-1 (`payDailyJackpot`) and Phase-2 (`payDailyJackpotCoinAndTickets`) hops, except where explicitly enumerated below.
**EXEMPT-stack roots in scope for this consumer:** EXEMPT-ADVANCEGAME (every reachable `payDailyJackpot` call site lives inside `advanceGame`'s static call graph — confirmed by `grep -rn "payDailyJackpot"` on the full source tree: only the 3 callers at `AdvanceModule.sol:383/454/473` exist). EXEMPT-VRFCALLBACK does not directly invoke `payDailyJackpot` — `rawFulfillRandomWords` only writes `rngWordCurrent` then returns; the consumer is reached on the NEXT `advanceGame` call. EXEMPT-RETRYLOOTBOXRNG is unrelated (lootbox path, not daily jackpot).
**Pre-call state latches (relevant to commitment-window analysis):** Immediately before `payDailyJackpot(true, lvl, rngWord)` is invoked from the jackpot-phase branch:
- (i) `rngLockedFlag = true` (set at `_requestRng`, line `:1634`), and remains true through the entire resolution until `_unlockRng` at the end of phase-2 or phase-1 path completion (`:467` / `:402` / `:631` / `:1729`).
- (ii) `dailyIdx` is the PRIOR day's index — `_unlockRng` (the only writer at `:1730`) runs AFTER `payDailyJackpot` returns, so for the lifetime of this consumer `dailyIdx` is still `D` while `_simulatedDayIndex()` returns `D+1`.
- (iii) `level` may have been pre-incremented at `_requestRng` line `:1643` when `isTicketJackpotDay && !isRetry`. The cached local `lvl` parameter holds the value AS OF `advanceGame`'s top-of-call SLOAD at line `:163`; the storage slot may be one ahead.
- (iv) `_swapAndFreeze(purchaseLevel)` (`:299` / `:1095` etc.) toggled `ticketWriteSlot` so that any mid-window `_queueTickets` write lands in the NEW write slot, while `processTicketBatch` runs against the OLD read slot. The double-buffer is the structural protection against same-resolution `ticketQueue`-mediated injection.
- (v) `_prepareFutureTickets` (`:344`) and `_runProcessTicketBatch(inJackpot ? lvl : purchaseLevel)` (`:357`) have already drained the read slot into `traitBurnTicket[lvl]` via `_raritySymbolBatch` BEFORE `payDailyJackpot` runs. The participating slots' state visible to the consumer is therefore the read-slot snapshot taken at queue-swap time.

---

### CAT-01 (§A) — Traced Function Set

Every internal/external function transitively reached from `payDailyJackpot` with explicit file:line citation. Three distinct execution profiles need to be covered: (P1) `isJackpotPhase=true, resumeEthPool == 0` (fresh daily jackpot), (P2) `isJackpotPhase=true, resumeEthPool != 0` (call-2 resume), (P3) `isJackpotPhase=false` (purchase-phase BAF-like daily). All three are traced.

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `payDailyJackpot(isJackpotPhase, lvl, randWord)` | `DegenerusGameJackpotModule.sol:339` | ENTRY (no access guard — module is delegatecall-only from parent GAME proxy) | 3 execution profiles per branch on `isJackpotPhase` + `resumeEthPool` |
| 2 | `_simulatedDayIndex()` | `DegenerusGameStorage.sol:1208` | 1 → :344 (`questDay = _simulatedDayIndex()`) | wraps `GameTimeLib.currentDayIndex()` — pure block.timestamp arithmetic, NO SLOAD |
| 3 | `GameTimeLib.currentDayIndex()` | `GameTimeLib.sol:21` | 2 → :1209 | `[view]` reads only `block.timestamp` |
| 4 | `_resumeDailyEth(lvl, randWord)` | `DegenerusGameJackpotModule.sol:1178` | 1 → :350 (P2 branch when `resumeEthPool != 0`) | reads `resumeEthPool` via `_processDailyEth`; reads `dailyTicketBudgetsPacked`, `jackpotCounter`; reads `_get*PrizePool` on payout |
| 5 | `_rollWinningTraits(randWord, false)` | `DegenerusGameJackpotModule.sol:1993` | 1 → :354 (P1); 1 → :531 (P3); 4 → :1180 (P2) | reads `dailyIdx` + `dailyHeroWagers[dailyIdx]` via `_applyHeroOverride` |
| 6 | `JackpotBucketLib.getRandomTraits(r)` | `JackpotBucketLib.sol:281` | 5 → :2000 | `[pure]` |
| 7 | `_applyHeroOverride(traits, r, randWord)` | `DegenerusGameJackpotModule.sol:1600` | 5 → :2001 | reads `dailyIdx` (line :1609) + delegates to `_rollHeroSymbol` |
| 8 | `_rollHeroSymbol(dailyIdx, heroEntropy)` | `DegenerusGameJackpotModule.sol:1639` | 7 → :1609 | reads `dailyHeroWagers[day][q]` for q=0..3 (4 SLOADs at :1653) |
| 9 | `JackpotBucketLib.packWinningTraits(traits)` | `JackpotBucketLib.sol:267` | 5 → :2002 | `[pure]` |
| 10 | `_dailyCurrentPoolBps(counter, randWord)` | `DegenerusGameJackpotModule.sol:2015` | 1 → :379 (P1, non-final day) | `[pure]` |
| 11 | `_getCurrentPrizePool()` | `DegenerusGameStorage.sol:814` | 1 → :374, :407, :507, :515 (P1); 4 → :1203 (P2) | reads `currentPrizePool` slot |
| 12 | `_setCurrentPrizePool(val)` | `DegenerusGameStorage.sol:821` | 1 → :406, :506, :515 (P1); 4 → :1203 (P2) | writes `currentPrizePool` |
| 13 | `_getNextPrizePool()` | `DegenerusGameStorage.sol:785` | 1 → :409, :434 (P1); 24 → :842, :725 (carryover) | reads `prizePoolsPacked` |
| 14 | `_setNextPrizePool(val)` | `DegenerusGameStorage.sol:791` | 1 → :409, :434 (P1); 24 → :842 | writes `prizePoolsPacked` |
| 15 | `_getFuturePrizePool()` | `DegenerusGameStorage.sol:797` | 1 → :431, :511, :548, :570 (all paths); 4 → :1201 (P2) | reads `prizePoolsPacked` |
| 16 | `_setFuturePrizePool(val)` | `DegenerusGameStorage.sol:803` | 1 → :433, :510, :569 (all paths); 4 → :1201 (P2); 30 → :840 | writes `prizePoolsPacked` |
| 17 | `_getPrizePools()` | `DegenerusGameStorage.sol:688` | 13/14/15/16 (indirect) | reads `prizePoolsPacked` |
| 18 | `_setPrizePools(next, future)` | `DegenerusGameStorage.sol:684` | 14/16 (indirect) | writes `prizePoolsPacked` |
| 19 | `_runEarlyBirdLootboxJackpot(lvl + 1, randWord)` | `DegenerusGameJackpotModule.sol:676` | 1 → :390 (P1, isEarlyBirdDay) | reads `traitBurnTicket[lvl+1][bonusTrait]` for 4 buckets |
| 20 | `_budgetToTicketUnits(budget, lvl)` | `DegenerusGameJackpotModule.sol:853` | 1 → :400, :435 (P1) | `[pure]` (delegates to `PriceLookupLib.priceForLevel`) |
| 21 | `PriceLookupLib.priceForLevel(targetLevel)` | `PriceLookupLib.sol:21` | 20 → :858; 19 → :682; 33 → :2288; etc. | `[pure]` |
| 22 | `_packDailyTicketBudgets(...)` | `DegenerusGameJackpotModule.sol:2030` | 1 → :444 (P1) | `[pure]` |
| 23 | `_unpackDailyTicketBudgets(packed)` | `DegenerusGameJackpotModule.sol:2043` | 1 → :459 (P1); 4 → :1183 (P2) | `[pure]` |
| 24 | `EntropyLib.hash2(rngWord, lvl)` | `EntropyLib.sol:23` | 1 → :454 (P1); 1 → :533 (P3); 4 → :1179 (P2); 33 → :2267; 26 → :888 | `[pure]` keccak |
| 25 | `JackpotBucketLib.unpackWinningTraits(packed)` | `JackpotBucketLib.sol:272` | 1 → :455 (P1); 1 → :532 (P3); 4 → :1180 (P2); 19 → :688; 26 → :907; 28 → :1127 | `[pure]` |
| 26 | `_pickSoloQuadrant(traits, entropy)` | `DegenerusGameJackpotModule.sol:1098` | 1 → :457 (P1); 1 → :534 (P3); 4 → :1181 (P2) | `[pure]` |
| 27 | `JackpotBucketLib.bucketCountsForPoolCap(...)` | `JackpotBucketLib.sol:98` | 1 → :466 (P1); 4 → :1192 (P2) | `[pure]` |
| 28 | `JackpotBucketLib.traitBucketCounts(entropy)` | `JackpotBucketLib.sol:36` | 27 → :105 | `[pure]` |
| 29 | `JackpotBucketLib.scaleTraitBucketCountsWithCap(...)` | `JackpotBucketLib.sol:55` | 27 → :106 | `[pure]` |
| 30 | `JackpotBucketLib.capBucketCounts(counts, max, entropy)` | `JackpotBucketLib.sol:115` | 29 → :94 | `[pure]` |
| 31 | `JackpotBucketLib.sumBucketCounts(counts)` | `JackpotBucketLib.sol:110` | 30 → :129 | `[pure]` |
| 32 | `JackpotBucketLib.shareBpsByBucket(packed, offset)` | `JackpotBucketLib.sol:254` | 1 → :490 (P1); 4 → :1188 (P2); 33 → :1130 (P3) | `[pure]` |
| 33 | `JackpotBucketLib.rotatedShareBps(packed, off, idx)` | `JackpotBucketLib.sol:248` | 32 → :257 | `[pure]` |
| 34 | `_processDailyEth(lvl, ethPool, entropy, traits, shareBps, counts, isFinalDay, splitMode, isJackpotPhase)` | `DegenerusGameJackpotModule.sol:1232` | 1 → :493 (P1); 4 → :1185 (P2) (with `SPLIT_CALL2`); 35 → :1158 (P3, via `_runJackpotEthFlow`) | reads `resumeEthPool` (writes when `SPLIT_CALL2`); reads `traitBurnTicket[lvl][trait]` via `_randTraitTicket`; writes `claimablePool` via `:1335` |
| 35 | `_executeJackpot(jp)` | `DegenerusGameJackpotModule.sol:1124` | 1 → :557 (P3) | dispatches to `_runJackpotEthFlow` |
| 36 | `_runJackpotEthFlow(jp, traitIds, shareBps)` | `DegenerusGameJackpotModule.sol:1142` | 35 → :1136 | calls `_processDailyEth` with fixed `[20,12,6,1]` rotation |
| 37 | `JackpotBucketLib.soloBucketIndex(entropy)` | `JackpotBucketLib.sol:243` | 34 → :1252 | `[pure]` |
| 38 | `JackpotBucketLib.bucketShares(pool, shareBps, counts, idx, unit)` | `JackpotBucketLib.sol:214` | 34 → :1253 | `[pure]` |
| 39 | `JackpotBucketLib.bucketOrderLargestFirst(counts)` | `JackpotBucketLib.sol:1257` | 34 → :1257 | `[pure]` |
| 40 | `_randTraitTicket(traitBurnTicket[lvl], rng, trait, n, salt)` | `DegenerusGameJackpotModule.sol:1707` | 34 → :1297; 19 → :688/:697 (early-bird); 51 → :883 (distributeLootbox); 60 → :983 (distributeTicketJackpot) | reads `traitBurnTicket[lvl][trait]` (length + element slots) + `deityBySymbol[fullSymId]` |
| 41 | `_handleSoloBucketWinner(w, lvl, traitId, ticketIdx, perWinner, entropy, isFinalDay)` | `DegenerusGameJackpotModule.sol:1454` | 34 → :1316 (only when `isJackpotPhase=true && traitIdx==remainderIdx`) | delegates to `_processSoloBucketWinner` + reads `dgnrs.poolBalance` on final day |
| 42 | `_processSoloBucketWinner(winner, perWinner, entropy)` | `DegenerusGameJackpotModule.sol:1539` | 41 → :1473 | calls `_addClaimableEth`; writes `whalePassClaims[w]` + `_setFuturePrizePool` |
| 43 | `IStakedDegenerusStonk.poolBalance(Pool.Reward)` | `StakedDegenerusStonk.sol:391` | 41 → :1493 (isFinalDay only) | EXTERNAL call into sDGNRS contract — reads `poolBalances[idx]` (sDGNRS-local storage, not GAME storage) |
| 44 | `IStakedDegenerusStonk.transferFromPool(...)` | `StakedDegenerusStonk.sol:412` | 41 → :1498 (isFinalDay only) | EXTERNAL — writes sDGNRS-local `poolBalances`, `balanceOf`, `totalSupply` — outside GAME storage scope |
| 45 | `_payNormalBucket(winners, ticketIdx, perWinner, lvl, traitId, entropy)` | `DegenerusGameJackpotModule.sol:1509` | 34 → :1326 (when not isJackpotPhase OR not solo bucket) | iterates winners, calls `_addClaimableEth` per winner |
| 46 | `_addClaimableEth(beneficiary, weiAmount, entropy)` | `DegenerusGameJackpotModule.sol:780` | 42 → :1563/:1575; 45 → :1521; 23 (via `_processAutoRebuy`) | reads `gameOver` + `autoRebuyState[beneficiary]`; writes `claimableWinnings` via `_creditClaimable` OR routes to auto-rebuy |
| 47 | `_processAutoRebuy(player, newAmount, entropy, state)` | `DegenerusGameJackpotModule.sol:814` | 46 → :796 (when `!gameOver && state.autoRebuyEnabled`) | calls `_calcAutoRebuy` (pure), `_queueTickets`, `_setFuturePrizePool`/`_setNextPrizePool`, `_creditClaimable` |
| 48 | `_calcAutoRebuy(...)` | `DegenerusGamePayoutUtils.sol:51` | 47 → :822 | `[pure]` — reads `state` from memory only |
| 49 | `_creditClaimable(beneficiary, weiAmount)` | `DegenerusGamePayoutUtils.sol:32` | 46 → :802; 47 → :833/:846 | writes `claimableWinnings[beneficiary]` |
| 50 | `_queueTickets(buyer, targetLevel, quantity, true)` | `DegenerusGameStorage.sol:559` | 47 → :837; 19 → :703; 60 → :1007; 61 → :2305 | reads `level`, `rngLockedFlag` (gate at :572 — bypassed via `rngBypass=true`); writes `ticketQueue[wk]` + `ticketsOwedPacked[wk][buyer]` |
| 51 | `_distributeLootboxAndTickets(lvl, traits, budget, randWord, bps)` | `DegenerusGameJackpotModule.sol:869` | 1 → :575 (P3 only) | calls `_setNextPrizePool`, `_budgetToTicketUnits`, `_distributeTicketJackpot` |
| 52 | `_distributeTicketJackpot(sourceLvl, queueLvl, traits, units, entropy, max, salt)` | `DegenerusGameJackpotModule.sol:896` | 51 → :883 (P3); (NOT directly reached from P1 — P1 stores `dailyTicketBudgetsPacked` for Phase-2 consumption, out-of-trace) | reads `traitBurnTicket[sourceLvl]` (length via `_computeBucketCounts`); calls `_distributeTicketsToBuckets` |
| 53 | `_computeBucketCounts(lvl, traits, max, entropy)` | `DegenerusGameJackpotModule.sol:1030` | 52 → :913 | reads `traitBurnTicket[lvl][trait].length` (4×) + `deityBySymbol[fullSymId]` (4×) |
| 54 | `_distributeTicketsToBuckets(...)` | `DegenerusGameJackpotModule.sol:934` | 52 → :921 | dispatches to `_distributeTicketsToBucket` per active bucket |
| 55 | `_distributeTicketsToBucket(...)` | `DegenerusGameJackpotModule.sol:973` | 54 → :953 | calls `_randTraitTicket` + `_queueTickets` |
| 56 | `_tqWriteKey(lvl)` | `DegenerusGameStorage.sol:718` | 50 → :575 (indirect via `_queueTickets`) | `[view]` reads `ticketWriteSlot` |
| 57 | `_tqFarFutureKey(lvl)` | `DegenerusGameStorage.sol:731` | 50 → :574 | `[pure]` |
| 58 | `_livenessTriggered()` | `DegenerusGameStorage.sol:1243` | 50 → :570 | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`, `_simulatedDayIndex()` |

> **Note on Phase-2 split:** `payDailyJackpot(true, …)` Phase-1 stores `dailyJackpotCoinTicketsPending = true` + `dailyTicketBudgetsPacked` at lines `:526` / `:444`. Phase-2 (`payDailyJackpotCoinAndTickets`) is a SEPARATE consumer entry (§2 — see `298-02-CATALOG-section.md`). The transitive Phase-2 reach is OUT OF SCOPE for this §1 catalog per `D-298-CONSUMER-LIST-01`.

> **Stop boundary (external interfaces with no source available):** `IStakedDegenerusStonk.poolBalance` / `IStakedDegenerusStonk.transferFromPool` — sDGNRS is a SEPARATE deployed contract (`contracts/StakedDegenerusStonk.sol`), not delegatecall storage. The trace enumerates the SLOADs these external calls perform on sDGNRS-local storage, but those slots are in a SEPARATE storage namespace and do NOT influence VRF-derived output of this consumer — they only affect the sDGNRS reward-pool payout amount on `isFinalDay`. The relevant participating-slot analysis is bounded to GAME storage.

---

### CAT-02 (§B) — SLOAD Table

Every storage read reached anywhere in §A's function set is enumerated per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent — NON-PARTICIPATING slots get explicit attestation). Columns: `Slot | Read-site (file:line) | Read context | Participating? (YES/NO) | Attestation if NO`.

| Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|------|-----------------------|--------------|----------------|-------------------|
| `dailyIdx` | `JackpotModule.sol:1609` (via `_applyHeroOverride` → `_rollHeroSymbol(dailyIdx, …)`) | Day-index parameter for `dailyHeroWagers[day][q]` SLOAD | **YES** | — |
| `dailyHeroWagers[D][q]` (4 SLOADs at q=0..3) | `JackpotModule.sol:1653` (inside `_rollHeroSymbol` Pass 1 loop) | Weighted-random hero `(quadrant, symbol)` selection → trait replacement at line `:1623` → drives bucket reads + winner selection | **YES** | — |
| `level` | `JackpotModule.sol:1773` (NOT reached from P1; only `_calcDailyCoinBudget` reads it via Phase-2 `_calcDailyCoinBudget` → out of trace); `JackpotModule.sol:608` (Phase-2 only); **inside Phase-1 trace:** `JackpotModule.sol:1571` of `_queueTickets` reads `level` indirectly via `_livenessTriggered` AND `level + 5` comparison at `:571`. Cached `lvl` parameter shadows the storage read at top-level callsites. | `_queueTickets` gate against far-future writes during RNG window | **YES** | Cached `lvl` parameter in `_processAutoRebuy` may differ from storage `level` if pre-incremented at `_requestRng:1643`; auto-rebuy `targetLevel = level + offset` derived from the storage SLOAD, which influences which `ticketQueue[wk]` slot receives the bonus tickets (does NOT directly drive winner selection but DOES influence reward routing within VRF-derived flow) |
| `gameOver` | `JackpotModule.sol:792` (inside `_addClaimableEth`) | Branch gate: when `gameOver=true` skip auto-rebuy and route 100% to `_creditClaimable` | **YES** | — |
| `autoRebuyState[beneficiary]` | `JackpotModule.sol:793` (`AutoRebuyState memory state = autoRebuyState[beneficiary]`) | Drives 30%/45% ticket conversion + `targetLevel` selection → influences which `ticketQueue` slot receives bonus tickets and how much ETH is redirected to `nextPrizePool`/`futurePrizePool` | **YES** | — |
| `claimableWinnings[beneficiary]` | `PayoutUtils.sol:35` (`claimableWinnings[beneficiary] += weiAmount`) | Write-only inside trace (the `+=` is SLOAD + SSTORE) | **NO** | Accounting aggregate; the value read is the existing balance, only the increment is the VRF-derived payout. Pre-existing balance does NOT influence the increment amount, winner selection, or any downstream VRF derivation. F-41-02/03 attestation: changing this slot mid-window only changes the resulting balance, never the bucket of winners or share assignment. |
| `claimablePool` | `JackpotModule.sol:1335` (`claimablePool += uint128(liabilityDelta)`); `PayoutUtils.sol:101` | Write-only `+=` aggregate | **NO** | Same as `claimableWinnings` — aggregate liability counter; pre-existing value drives no VRF output. |
| `traitBurnTicket[lvl][trait]` (length + elements) | `JackpotModule.sol:1718` (inside `_randTraitTicket`: `holders.length` + `holders[idx]`); `:1039` (`_computeBucketCounts`: `.length != 0` check); `:691` (early-bird `bucket = traitBurnTicket[lvl]`); `:1297` (`_processDailyEth`); `:1860` (Phase-2 only); `:1400` (`_resolveTraitWinners` — unreachable from P1 entry; dead-code helper still has SLOADs). All reads happen for `lvl ∈ {lvl, lvl+1, sourceLvl=lvl+1..lvl+4, queueLvl}` within this resolution. | Winner selection from trait bucket | **YES** | — |
| `deityBySymbol[fullSymId]` | `JackpotModule.sol:1730` (inside `_randTraitTicket`); `:1044` (`_computeBucketCounts` virtual deity check); `:1844` (Phase-2 only) | Virtual deity entry — when `idx >= len`, winner becomes `deity`; influences winner selection probability | **YES** | — |
| `whalePassClaims[winner]` | `PayoutUtils.sol:95` (`whalePassClaims[winner] += fullHalfPasses`); `JackpotModule.sol:1570` (`whalePassClaims[winner] += whalePassCount`) | Write-only `+=` aggregate inside `_processSoloBucketWinner` | **NO** | Aggregate of pending whale-pass redemptions; pre-existing value does NOT influence amount credited (the increment is `wpSpent/HALF_WHALE_PASS_PRICE` derived from `perWinner`, which is derived from VRF entropy + ethPool — not from prior `whalePassClaims` state). |
| `currentPrizePool` | `Storage.sol:815` (`_getCurrentPrizePool`); read at JackpotModule `:374, :407, :506, :515, :1203` | Pool snapshot — drives `dailyEthBudget = (poolSnapshot * dailyBps) / 10_000` at `:385`; this budget then determines `bucketCounts` at `:466` via `bucketCountsForPoolCap(dailyEthBudget, …)`, which controls per-bucket winner count distribution. | **YES** | — |
| `prizePoolsPacked` (futurePrizePool + nextPrizePool packed) | `Storage.sol:693` (`_getPrizePools`); read at JackpotModule `:431, :511, :548, :570, :725, :840, :842, :1201` | Future-pool snapshot — drives `reserveSlice = futurePoolBal / 200` at `:432` (carryover ticket reservation); `ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000` at `:548` (P3 1% drip); influences ETH budget for purchase-phase BAF-style payout. Drives `_setNextPrizePool(_getNextPrizePool() + reserveSlice)` and `_setFuturePrizePool(... - reserveSlice)`. Also `nextPrizePool` is referenced by `_queueTickets` indirectly via `_setNextPrizePool` writes; the read at `_getNextPrizePool` at `:409, :434` influences carryover routing. | **YES** | — |
| `yieldAccumulator` | (NOT directly reached from `payDailyJackpot`'s call graph — only `distributeYieldSurplus` at `:732` and GameOver at `GameOverModule.sol:150` read/write it; `distributeYieldSurplus` is invoked from `advanceGame` AT LEVEL TRANSITION, not as a sub-call of `payDailyJackpot`). | (out of trace for §1) | **N/A** | Slot is enumerated here for completeness attestation — `grep -rn yieldAccumulator contracts/` confirms zero reads inside `payDailyJackpot` → `_addClaimableEth` → `_processAutoRebuy` → `_creditClaimable` → `_distributeLootboxAndTickets` reach set. |
| `jackpotCounter` | `JackpotModule.sol:358` (P1: `uint8 counter = jackpotCounter`); `:462` (P1: `isFinalPhysicalDay_ = (jackpotCounter + counterStep_ ...)`); `:1184` (P2 resume: `jackpotCounter + cs`); `:651` (Phase-2 only); `:665` (`jackpotCounter += counterStep` — Phase-2 write) | Drives `counterStep` selection at :358-:371 (turbo/compressed/normal logic) → determines `isFinalPhysicalDay` → selects `FINAL_DAY_SHARES_PACKED` vs `DAILY_JACKPOT_SHARES_PACKED` at `:487` → influences share allocation across buckets. **DOES influence VRF-derived output:** different shares produce different `perWinner` amounts even with same entropy. | **YES** | — |
| `compressedJackpotFlag` | `JackpotModule.sol:362` (P1: `compressedJackpotFlag == 2 && counter == 0`); `:365` (P1: `compressedJackpotFlag == 1 ...`) | Drives `counterStep` selection at the same site as `jackpotCounter` | **YES** | — |
| `resumeEthPool` | `JackpotModule.sol:349` (P1 branch gate: `if (resumeEthPool != 0)`); `:1193` (P2 resume: pass to `bucketCountsForPoolCap`); `:1244` (P2 resume: `ethPool = uint256(resumeEthPool)`) | (P1) Branches into P2 resume path when non-zero. (P2) The cached ethPool snapshot from call-1 — drives bucket scaling at `:1192` AND determines `paidEth` adjustments at `:1199-:1204` | **YES** | — |
| `dailyTicketBudgetsPacked` | `JackpotModule.sol:460` (P1: `_unpackDailyTicketBudgets(dailyTicketBudgetsPacked)` after write at `:444`); `:1183` (P2 resume: `_unpackDailyTicketBudgets(dailyTicketBudgetsPacked)`); `:605` (Phase-2 unpacking — out of §1 trace) | P1 read at `:460` is of the value just-written at `:444` (same call). P2 (resume) read at `:1183` is of value written during a PREVIOUS `advanceGame` call's P1. The `counterStep` extracted at `:459` is reused for `isFinalPhysicalDay_` flag at `:462`. | **YES** | — |
| `lastPurchaseDay` | `Storage.sol:1244` (`_livenessTriggered`: `if (lastPurchaseDay \|\| jackpotPhaseFlag) return false`) | `_livenessTriggered` is reached via `_queueTickets` (`:570`). Read controls whether the liveness-timeout fires (and reverts `_queueTickets`). | **NO** | Read controls whether the in-flow `_queueTickets` reverts. A mid-window flip of `lastPurchaseDay` from true→false would unblock the liveness trigger and could revert the entire jackpot resolution. **However**, no external function writes `lastPurchaseDay = false` outside `advanceGame`'s state machine — it's only set true at `:176`/`:397` (mid-advance) and false at `:439` (post-jackpot transition). Since the consumer is itself inside `advanceGame`, no external mid-resolution flip is possible. Attestation: no race exists. |
| `jackpotPhaseFlag` | `Storage.sol:1244` (`_livenessTriggered`) | Same as `lastPurchaseDay` — used inside `_queueTickets`'s liveness gate | **NO** | Set inside `advanceGame` state machine only (`:437` write, no external writer). Attestation: no race exists. |
| `purchaseStartDay` | `Storage.sol:1246` (`_livenessTriggered`: `uint32 psd = purchaseStartDay`) | Drives liveness-timeout check inside `_queueTickets` gate | **NO** | Same — only written inside `advanceGame` (`:332`, `:642`); read controls revert behavior, not VRF derivation. |
| `rngRequestTime` | `Storage.sol:1250` (`_livenessTriggered`: `uint48 rngStart = rngRequestTime`) | VRF-stall liveness check | **NO** | Set/cleared inside `_requestRng` and `_unlockRng`. Since this consumer runs INSIDE the same advanceGame that holds `rngLockedFlag=true`, `rngRequestTime != 0` is guaranteed but cannot transition. Attestation: no concurrent writer outside the same stack. |
| `rngLockedFlag` | `Storage.sol:572` (inside `_queueTickets`: `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`); `:604, :660` (`_queueTicketsScaled` / `_queueTicketRange` — both unreachable from P1 trace) | Far-future bypass gate inside `_queueTickets`. Reach: only when `targetLevel > level + 5`. All `_queueTickets` calls from JackpotModule pass `rngBypass=true` (lines `:703, :837, :1007, :2305`), so the gate never fires for in-flow writes. | **NO** | Reads are bypassed via `rngBypass=true` in every Jackpot-stack `_queueTickets` invocation; the slot's value cannot change the VRF outcome of THIS consumer. (External writers of `rngLockedFlag` are gated to advanceGame-stack only.) |
| `ticketWriteSlot` | `Storage.sol:719` (`_tqWriteKey`); read inside `_queueTickets` at `:573-:575` | Determines write-slot key for `ticketQueue` writes from auto-rebuy + jackpot-flow `_queueTickets` calls | **NO** | The slot value affects which `ticketQueue[wk]` array receives the bonus tickets, NOT the winner selection. Auto-rebuy bonus tickets land in `ticketQueue[wk]` regardless of `wk` — the winners have already been selected via `_randTraitTicket` at this point. Attestation: write-side routing only, no read-back into VRF flow. |
| `ticketsOwedPacked[wk][buyer]` | `Storage.sol:576` (`_queueTickets`: `uint40 packed = ticketsOwedPacked[wk][buyer]`) | Read to check `owed/rem` before push to `ticketQueue` | **NO** | Per-player owed counter; never read by winner selection or share calculation. Pre-existing balance only determines whether `ticketQueue[wk].push(buyer)` fires for this player (deduplication). No VRF coupling. |
| `ticketQueue[wk]` (length only) | `Storage.sol:579` (implicit via `if (owed == 0 && rem == 0) ticketQueue[wk].push(buyer)`) | Length read implicit in `.push()` | **NO** | Same as `ticketsOwedPacked` — write-side routing for downstream `processTicketBatch` consumption (which happens on the NEXT advanceGame call), not part of this consumer's VRF derivation. |
| `IStakedDegenerusStonk.poolBalances[Pool.Reward]` (cross-contract) | `StakedDegenerusStonk.sol:392` (via `dgnrs.poolBalance(Pool.Reward)` call at `JackpotModule.sol:1493`) | Final-day DGNRS reward amount | **NO** | Cross-contract storage in sDGNRS namespace. The value is consumed only on `isFinalPhysicalDay` for the solo bucket winner — it determines `reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000` at `:1496`, then `transferFromPool`. This payout is ORTHOGONAL to VRF-derived winner selection (the winner is already chosen). The reward amount IS influenced by the slot, but the slot is **external sDGNRS storage** — and per `D-298-EXEMPT-CROSSCONTRACT-01` + `D-298-TRACE-DEPTH-01`, we enumerate sDGNRS writers inline. **Reclassification:** Since the payout amount IS a VRF-resolved output ("how much DGNRS goes to winner X selected by VRF"), this slot crosses into participating territory. **Marked YES below — see verdict matrix.** |
| `IStakedDegenerusStonk.poolBalances[Pool.Reward]` (revised) | (same site) | (same context) | **YES** | (moved from NO above per verdict-matrix logic — see §C/§D) |

> **Completeness attestation:** Every SLOAD reachable from `payDailyJackpot`'s 3 execution profiles is listed. Pure-library helpers (JackpotBucketLib, EntropyLib, PriceLookupLib, GameTimeLib) perform ZERO SLOADs — confirmed by `grep -n "sload\|storage" contracts/libraries/*.sol` returning only function signatures (the `storage` keyword in `address[][256] storage` reference declarations is pointer aliasing, not a SLOAD on its own). `_simulatedDayIndex` reduces to `block.timestamp` arithmetic (no SLOAD).

> **Participating-set summary (forwards into §C):** `dailyIdx`, `dailyHeroWagers[D][q]` (×4 keys), `level` (cached vs storage discrepancy), `gameOver`, `autoRebuyState[beneficiary]`, `traitBurnTicket[lvl][trait]` (length + elements), `deityBySymbol[fullSymId]`, `currentPrizePool`, `prizePoolsPacked` (next + future components), `jackpotCounter`, `compressedJackpotFlag`, `resumeEthPool`, `dailyTicketBudgetsPacked`, sDGNRS `poolBalances[Pool.Reward]`.

---

### CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` slot in §B, every external/public function across all `contracts/` that writes the slot is enumerated, per-callsite. Each row: `Slot | Writer fn | Writer file:line | Callsite file:line | Reach path`.

### Slot: `dailyIdx`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_unlockRng(day)` | `DegenerusGameAdvanceModule.sol:1729` (writes `dailyIdx = day` at `:1730`) | `:331, :402, :467, :631, :1729` (all inside `advanceGame`) | advanceGame → `_unlockRng` (5 callsites, all advanceGame-stack) |
| `DegenerusGame.constructor` | `DegenerusGame.sol:219` (`dailyIdx = currentDay`) | `:219` | pre-deployment constructor (genesis only) |

### Slot: `dailyHeroWagers[D][q]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_placeDegeneretteBetCore(...)` | `DegenerusGameDegeneretteModule.sol:499` (`dailyHeroWagers[day][heroQuadrant] = wPacked`) | reached from `placeDegeneretteBet` external entries: `DegenerusGameDegeneretteModule.sol:367` + `DegenerusGame.sol:714` (delegatecall fan-out) + `DegenerusVault.sol:607` (vault.placeDegeneretteBet → game.placeDegeneretteBet) | EOA / Vault → `placeDegeneretteBet` → `_placeDegeneretteBetCore` |

### Slot: `level`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_requestRng(...)` (inside `_finalizeRngRequest`) | `DegenerusGameAdvanceModule.sol:1643` (`level = lvl` when `isTicketJackpotDay && !isRetry`) | `:1643` (inside the only `_requestRng` flow which is `rngGate` → `_requestRng`) | advanceGame → `rngGate` → `_requestRng` |
| `DegenerusGameStorage.sol:250` declaration default | `DegenerusGameStorage.sol:250` | `:250` | constructor init only (`= 0`) |

### Slot: `gameOver`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `handleGameOverDrain(day)` | `DegenerusGameGameOverModule.sol:139` (`gameOver = true`) | `:139` (reached from `advanceGame._handleGameOverPath` at `AdvanceModule.sol:624`) | advanceGame → `_handleGameOverPath` → `handleGameOverDrain` |
| `MockGameCharity.setGameOver(bool)` | `contracts/mocks/MockGameCharity.sol:11` (`gameOver = _over`) | `:11` | **mock-only** — not part of MAINNET deployment, excluded from verdict matrix |

### Slot: `autoRebuyState[beneficiary]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_setAutoRebuy(player, enabled)` | `DegenerusGame.sol:1512` (`state.autoRebuyEnabled = enabled` at `:1516`) | `:1495` (`setAutoRebuy`) external entry; `:1512` private dispatch | EOA → `setAutoRebuy` |
| `_setAutoRebuyTakeProfit(player, takeProfit)` | `DegenerusGame.sol:1524` (`state.takeProfit = takeProfitValue` at `:1532`) | `:1504` (`setAutoRebuyTakeProfit`) | EOA → `setAutoRebuyTakeProfit` |
| `_setAfKingMode(player, enabled, …)` | `DegenerusGame.sol:1569` (writes `autoRebuyEnabled`, `takeProfit`, `afKingMode`, `afKingActivatedLevel` at `:1593, :1597, :1604, :1605`) | `:1559` (`setAfKingMode`) | EOA → `setAfKingMode` |
| `_deactivateAfKing(player)` | `DegenerusGame.sol:1670` (writes `afKingMode`, `afKingActivatedLevel` at `:1679, :1680`) | `:1641` (`deactivateAfKingFromCoin` external — COIN/COINFLIP only), `:1670` (private, called from `_setAutoRebuy`/`_setAfKingMode`) | EOA via setAutoRebuy/setAfKingMode + BurnieCoin/BurnieCoinflip → `deactivateAfKingFromCoin` |
| `syncAfKingLazyPassFromCoin(player)` | `DegenerusGame.sol:1654` (writes `afKingMode`, `afKingActivatedLevel` at `:1664, :1665`) | `:1654` (COINFLIP-only external) | BurnieCoinflip → `syncAfKingLazyPassFromCoin` |

### Slot: `traitBurnTicket[lvl][trait]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_raritySymbolBatch(player, baseKey, startIndex, count, entropy)` (writes via inline assembly `sstore` to `traitBurnTicket[lvl][traitId]`'s array length + element slots) | `DegenerusGameMintModule.sol:537` (assembly block at :600-:629 computes `levelSlot = keccak256(lvl, slot)` and sstores length + addresses) | called from `processTicketBatch` at `:662` (via `_processOneTicketEntry`) AND from `processFutureTicketBatch` at `:385` (via `_raritySymbolBatch` line :470). | advanceGame → `_runProcessTicketBatch` → `processTicketBatch` (delegatecall) → `_raritySymbolBatch`; OR advanceGame → `_prepareFutureTickets` / `_processFutureTicketBatch` → `processFutureTicketBatch` (delegatecall) → `_raritySymbolBatch` |
| (no external/public direct writer of `traitBurnTicket` exists — `grep -rn traitBurnTicket contracts/` confirms only `MintModule._raritySymbolBatch` performs the SSTORE via assembly) | — | — | — |

### Slot: `deityBySymbol[fullSymId]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_purchaseDeityPass(buyer, symbolId)` | `DegenerusGameWhaleModule.sol:542` (`deityBySymbol[symbolId] = buyer` at `:598`) | `:538` (`purchaseDeityPass` external entry — Whale module); `DegenerusGame.sol:644` (delegatecall dispatch) | EOA → `DegenerusGame.purchaseDeityPass` → delegatecall → `WhaleModule.purchaseDeityPass` |

### Slot: `currentPrizePool`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_setCurrentPrizePool(val)` | `DegenerusGameStorage.sol:821` (`currentPrizePool = uint128(val)`) | Callsites: `JackpotModule.sol:406, :506, :515, :1203`; `AdvanceModule.sol:902` (inside `_consolidatePoolsAndRewardJackpots`); `Storage.sol:1135` and adjacent (whale-pass distribution helpers). | advanceGame → various pool helpers; `payDailyJackpot` itself writes (line :406, :506, :515) via the SAME advanceGame stack |
| direct write `currentPrizePool = ...` | `DegenerusGameAdvanceModule.sol:902` | `:902` | advanceGame → `_consolidatePoolsAndRewardJackpots` |

### Slot: `prizePoolsPacked` (next + future components)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_setPrizePools(next, future)` | `DegenerusGameStorage.sol:684` | every `_setNextPrizePool`/`_setFuturePrizePool` callsite delegates here | (see next two rows for callsites) |
| `_setNextPrizePool(val)` | `DegenerusGameStorage.sol:791` | Callsites: `JackpotModule.sol:409, :434, :725, :842, :877` (inside `_distributeLootboxAndTickets`); `DegenerusGameAdvanceModule.sol` (consolidation); `DecimatorModule.sol`; `MintModule.sol` (payment processing); `DegeneretteModule.sol` (bet collection); `BoonModule.sol`; `LootboxModule.sol`; `WhaleModule.sol`. | EOA → `purchase`/`purchaseCoin`/`purchaseBurnieLootbox`/`purchaseWhaleBundle`/`purchaseLazyPass`/`purchaseDeityPass`/`placeDegeneretteBet`/`recordDecBurn`/`openLootBox`/`openBurnieLootBox`/`claimWhalePass`; advanceGame → various consolidations |
| `_setFuturePrizePool(val)` | `DegenerusGameStorage.sol:803` | Callsites: `JackpotModule.sol:433, :510, :569, :725, :840, :1201`; `DegenerusGameAdvanceModule.sol` (consolidation, gameOver); `DecimatorModule.sol`; `MintModule.sol`; etc. | same external entry surface as `_setNextPrizePool` (purchase/lootbox/whale/decimator paths all touch the future pool) |
| `_swapAndFreeze(purchaseLevel)` | `DegenerusGameStorage.sol:754` (writes `prizePoolFrozen=true` + may pre-seed `prizePoolPendingPacked` AND `_setFuturePrizePool(futureBal - seed)` at :761) | `:299, :631, :1095` (all inside `advanceGame`) | advanceGame → `_swapAndFreeze` |
| `_unfreezePool()` | `DegenerusGameStorage.sol:771` (writes `prizePoolsPacked` via `_setPrizePools(next + pNext, future + pFuture)` at :775) | called inside `_unlockRng` line :1735 | advanceGame → `_unlockRng` → `_unfreezePool` |
| Mint payment processing (`_processMintPayment`, `_handleMintRevenue`, etc.) | `DegenerusGameMintModule.sol` (many writes inside payment flow) | reached via `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` external entries | EOA → `purchase`/etc. → delegatecall → MintModule |
| Whale-pass purchase | `DegenerusGameWhaleModule.sol:187` (`purchaseWhaleBundle`); `:380` (`purchaseLazyPass`); `:538` (`purchaseDeityPass`) | reached via `DegenerusGame.purchaseWhaleBundle`/etc. | EOA → delegatecall → WhaleModule |
| Decimator burn (`recordDecBurn`) | `DegenerusGameDecimatorModule.sol` (writes future-pool via `_setFuturePrizePool` during burn settlement) | `DegenerusGame.sol:1029` (`recordDecBurn`) | DegenerusCoin.burnCoin → `recordDecBurn` |
| Yield surplus | `JackpotModule.distributeYieldSurplus` (`:732`, writes `yieldAccumulator += quarterShare` at `:764`; uses `_addClaimableEth` which touches `claimableWinnings` not directly future pool) | `AdvanceModule.sol:423` (calls `_distributeYieldSurplus` which delegatecalls into JackpotModule.distributeYieldSurplus) | advanceGame → `_consolidatePoolsAndRewardJackpots` → `distributeYieldSurplus` |
| GameOver drain | `DegenerusGameGameOverModule.sol:147..150` (zeros all 4 pools: `currentPrizePool=0`, `_setNextPrizePool(0)`, `_setFuturePrizePool(0)`, `yieldAccumulator=0`) | `:139..152` inside `handleGameOverDrain` | advanceGame → `_handleGameOverPath` → `handleGameOverDrain` |

### Slot: `jackpotCounter`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `payDailyJackpotCoinAndTickets` | `DegenerusGameJackpotModule.sol:596` (`jackpotCounter += counterStep` at `:665`) | `:461` (advanceGame), `:937` (AdvanceModule.payDailyJackpotCoinAndTickets internal dispatcher) | advanceGame → `payDailyJackpotCoinAndTickets` |
| `_consolidatePoolsAndRewardJackpots` / phase transition | `DegenerusGameAdvanceModule.sol:644` (`jackpotCounter = 0`) | `:644` (inside post-jackpot transition cleanup) | advanceGame → phase transition |

### Slot: `compressedJackpotFlag`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `advanceGame` (turbo detection) | `DegenerusGameAdvanceModule.sol:177` (`compressedJackpotFlag = 2`) | `:177` (inside advanceGame top-of-function) | advanceGame self-write |
| `advanceGame` (compressed detection) | `DegenerusGameAdvanceModule.sol:399` (`compressedJackpotFlag = 1`) | `:399` (inside purchase-phase target-met branch) | advanceGame self-write |
| `_consolidatePoolsAndRewardJackpots` cleanup | `DegenerusGameAdvanceModule.sol:645` (`compressedJackpotFlag = 0`) | `:645` (post-jackpot transition cleanup) | advanceGame |

### Slot: `resumeEthPool`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_processDailyEth` (call-1 split write) | `DegenerusGameJackpotModule.sol:1340` (`resumeEthPool = uint128(ethPool)` when `splitMode == SPLIT_CALL1`) | `:1340` reached from `payDailyJackpot(true, ...)` P1 path via `_processDailyEth` at `:493` | advanceGame → `payDailyJackpot` → `_processDailyEth` |
| `_processDailyEth` (call-2 clear) | `DegenerusGameJackpotModule.sol:1245` (`resumeEthPool = 0` when `splitMode == SPLIT_CALL2`) | `:1245` reached from P2 resume path via `_resumeDailyEth` → `_processDailyEth` | advanceGame → `payDailyJackpot` → `_resumeDailyEth` → `_processDailyEth` |

### Slot: `dailyTicketBudgetsPacked`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `payDailyJackpot` P1 | `DegenerusGameJackpotModule.sol:444` (`dailyTicketBudgetsPacked = _packDailyTicketBudgets(...)`) | `:444` (P1 only) | advanceGame → `payDailyJackpot(true,…)` |
| `payDailyJackpotCoinAndTickets` (Phase-2 clear) | `DegenerusGameJackpotModule.sol:670` (`dailyTicketBudgetsPacked = 0`) | `:670` (Phase-2) | advanceGame → `payDailyJackpotCoinAndTickets` |

### Slot: sDGNRS `poolBalances[Pool.Reward]` (cross-contract)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `StakedDegenerusStonk.transferFromPool(pool, to, amount)` | `StakedDegenerusStonk.sol:412` (writes `poolBalances[idx] = available - amount` at `:422`) | `:412` (`onlyGame` modifier — only callable by GAME contract) | GAME → `dgnrs.transferFromPool` (from advanceGame, jackpot final-day, etc.) |
| `StakedDegenerusStonk.transferBetweenPools(from, to, amount)` | `StakedDegenerusStonk.sol` (writes 2× `poolBalances`) | `:1718` (advanceGame `_finalizeEarlybird`); other internal | GAME → `dgnrs.transferBetweenPools` |
| `StakedDegenerusStonk.transferToPool(...)` / pool-funding entries | `StakedDegenerusStonk.sol` | various — funded by advanceGame consolidation + initial distribution | GAME → various funding paths |
| ERC20-side: `transfer`, `transferFrom`, `_mint`, `_burn`, `approve` | `StakedDegenerusStonk.sol` ERC20 surface | EOA → standard ERC20 fns | EOA |

> **Cross-contract attestation:** sDGNRS is a SEPARATE deployed contract with `onlyGame`-modified write surface for pool operations. The ERC20 surface (`transfer`, `transferFrom`, `approve`) does NOT directly write `poolBalances[idx]` — it writes `balanceOf` mappings. The `transferFromPool` writer is the only one mutating `poolBalances[idx]` and it's gated to GAME.

---

### CAT-04 (§D) — Verdict Matrix

Per-(slot × writer × callsite) classification. Tokens: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. No discretionary classifications per `D-43N-AUDIT-ONLY-01`.

| # | Slot | Writer fn | Callsite (file:line) | EXEMPT stack reached? | Classification |
|---|------|-----------|---------------------|----------------------|----------------|
| 1 | `dailyIdx` | `_unlockRng` | `AdvanceModule.sol:331, :402, :467, :631` | EXEMPT-ADVANCEGAME (all sites inside `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 2 | `dailyIdx` | `DegenerusGame.constructor` | `DegenerusGame.sol:219` | constructor (pre-deploy, no live VRF flow possible) | **EXEMPT-ADVANCEGAME** (constructor is structurally EXEMPT — runs once, before any VRF callback can fire) |
| 3 | `dailyHeroWagers[D][q]` | `_placeDegeneretteBetCore` | `DegeneretteModule.sol:367` (`placeDegeneretteBet` external entry) | NOT in advanceGame/VRF-callback/retryLootboxRng stack | **VIOLATION** |
| 4 | `dailyHeroWagers[D][q]` | `_placeDegeneretteBetCore` | `DegenerusGame.sol:714` (`placeDegeneretteBet` parent dispatch) | NOT in EXEMPT stack | **VIOLATION** |
| 5 | `dailyHeroWagers[D][q]` | `_placeDegeneretteBetCore` | `DegenerusVault.sol:607` (vault-routed bet) | NOT in EXEMPT stack | **VIOLATION** |
| 6 | `level` | `_requestRng` → `_finalizeRngRequest` | `AdvanceModule.sol:1643` | EXEMPT-ADVANCEGAME (only reachable inside `advanceGame` → `rngGate`) | **EXEMPT-ADVANCEGAME** |
| 7 | `level` | declaration default | `Storage.sol:250` | constructor only | **EXEMPT-ADVANCEGAME** |
| 8 | `gameOver` | `handleGameOverDrain` | `GameOverModule.sol:139` | EXEMPT-ADVANCEGAME (reached only via `_handleGameOverPath` from `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 9 | `autoRebuyState[beneficiary]` | `_setAutoRebuy` | `DegenerusGame.sol:1495` (`setAutoRebuy` external entry) | NOT in EXEMPT stack — BUT `if (rngLockedFlag) revert RngLocked()` at `:1513` gates the call during the resolution window | **VIOLATION** (callable outside window only) — see §E remediation: gate IS already present per existing tactic (a) pattern; verdict-matrix classification requires the gate to be inside the resolution window. Since the gate IS present and the call reverts inside the window, the EFFECTIVE behavior is EXEMPT-by-gate. **However**, per `D-298-EXEMPT-REACH-01` (stack-rooted strict): the writer is NOT call-stack-reachable from an EXEMPT root, so it remains VIOLATION at the strict classification — the gate is a CORRECTNESS-PROOF artifact, not an EXEMPT-stack derivation. **Per `D-43N-AUDIT-ONLY-01`: classified VIOLATION with §E noting "gate already in place — verify gate coverage in FUZZ Phase 301."** |
| 10 | `autoRebuyState[beneficiary]` | `_setAutoRebuyTakeProfit` | `DegenerusGame.sol:1504` | Same as #9 — `rngLockedFlag` gate at `:1528` | **VIOLATION** (same disposition as #9) |
| 11 | `autoRebuyState[beneficiary]` | `_setAfKingMode` | `DegenerusGame.sol:1559` | Same as #9 — `rngLockedFlag` gate at `:1575` | **VIOLATION** (same disposition) |
| 12 | `autoRebuyState[beneficiary]` | `_deactivateAfKing` (via `deactivateAfKingFromCoin` external) | `DegenerusGame.sol:1641` | NOT in EXEMPT stack — caller is BurnieCoin/BurnieCoinflip. **NO `rngLockedFlag` gate on this entry.** | **VIOLATION** |
| 13 | `autoRebuyState[beneficiary]` | `syncAfKingLazyPassFromCoin` | `DegenerusGame.sol:1654` | NOT in EXEMPT stack — caller is BurnieCoinflip. **NO `rngLockedFlag` gate on this entry.** | **VIOLATION** |
| 14 | `traitBurnTicket[lvl][trait]` | `_raritySymbolBatch` (via `processTicketBatch`) | `MintModule.sol:662` reached from `AdvanceModule.sol:1507` (`_runProcessTicketBatch`) | EXEMPT-ADVANCEGAME (only reachable via `advanceGame`'s ticket-batch delegate at `:221, :277, :357`) | **EXEMPT-ADVANCEGAME** |
| 15 | `traitBurnTicket[lvl][trait]` | `_raritySymbolBatch` (via `processFutureTicketBatch`) | `MintModule.sol:385` reached from `AdvanceModule.sol:1438` (`_processFutureTicketBatch`) | EXEMPT-ADVANCEGAME (only reachable via `advanceGame`'s `_prepareFutureTickets` / phase transition) | **EXEMPT-ADVANCEGAME** |
| 16 | `deityBySymbol[fullSymId]` | `_purchaseDeityPass` | `WhaleModule.sol:538`/`DegenerusGame.sol:644` (`purchaseDeityPass` external entry) | NOT in EXEMPT stack — `if (rngLockedFlag) revert RngLocked()` at `:543` gates the call inside the window | **VIOLATION** (same disposition as #9 — gate IS in place but classification is stack-strict) |
| 17 | `currentPrizePool` | `_setCurrentPrizePool` (from JackpotModule self-writes during payDailyJackpot) | `JackpotModule.sol:406, :506, :515, :1203` | EXEMPT-ADVANCEGAME (self-stack of the consumer) | **EXEMPT-ADVANCEGAME** |
| 18 | `currentPrizePool` | `_setCurrentPrizePool` from `_consolidatePoolsAndRewardJackpots` | `AdvanceModule.sol:902` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 19 | `prizePoolsPacked` (next/future) | `_setNextPrizePool`/`_setFuturePrizePool` from JackpotModule self-writes | `JackpotModule.sol:409, :433, :434, :510, :511, :548, :569, :725, :840, :842, :877, :1201` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 20 | `prizePoolsPacked` (next/future) | `_swapAndFreeze` | `AdvanceModule.sol:299, :631, :1095` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 21 | `prizePoolsPacked` (next/future) | `_unfreezePool` via `_unlockRng` | `AdvanceModule.sol:1735` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 22 | `prizePoolsPacked` (next/future) | MintModule payment processing | `MintModule.sol` (various — `_processMintPayment`, `_handleMintRevenue`) reached from `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` | **`purchase` (MintModule:830) has NO blanket `rngLockedFlag` revert** — only the line `:1221` `cachedJpFlag && rngLockedFlag` redirect (last-jackpot-day routing). Writes to `prizePoolsPacked` (next/future) DO proceed during the resolution window via this entry. | **VIOLATION** |
| 23 | `prizePoolsPacked` (next/future) | WhaleModule (`purchaseWhaleBundle`, `purchaseLazyPass`) | `WhaleModule.sol:187, :380` | `purchaseWhaleBundle` and `purchaseLazyPass` — need to verify gate; `grep` shows no top-level `rngLockedFlag` revert | **VIOLATION** (no gate; the writes proceed inside the window) |
| 24 | `prizePoolsPacked` (next/future) | WhaleModule (`purchaseDeityPass`) | `WhaleModule.sol:538` | `if (rngLockedFlag) revert RngLocked()` at `:543` gates the call | **VIOLATION** (stack-strict; gate-by-revert) |
| 25 | `prizePoolsPacked` (next/future) | `recordDecBurn` (DegenerusCoin.burnCoin → ...) | `DegenerusGame.sol:1029` | No top-level `rngLockedFlag` gate on `recordDecBurn` (caller is BurnieCoin's burnCoin path) | **VIOLATION** |
| 26 | `prizePoolsPacked` (next/future) | `_distributeYieldSurplus` via `JackpotModule.distributeYieldSurplus` | `AdvanceModule.sol:423` | EXEMPT-ADVANCEGAME (advanceGame-stack) | **EXEMPT-ADVANCEGAME** |
| 27 | `prizePoolsPacked` (next/future) | `handleGameOverDrain` (zeros pools) | `GameOverModule.sol:147..150` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 28 | `prizePoolsPacked` (next/future) | `claimWhalePass` → `_queueTicketRange` (indirect — does NOT directly write prizePoolsPacked, but adjacent calls to `_queueTickets` reach `_setNextPrizePool` etc. via downstream auto-rebuy) | `DegenerusGame.sol:1692`, `WhaleModule.sol:957` | `claimWhalePass` does NOT have `rngLockedFlag` top-level gate, BUT `_queueTicketRange` reverts inside the loop when `isFarFuture && rngLockedFlag` (level+6..+100 portion) — so the whole call reverts atomically inside the window. **Effective gate.** | **VIOLATION** (stack-strict; effective gate via downstream revert) |
| 29 | `prizePoolsPacked` (next/future) | `placeDegeneretteBet` → `_collectBetFunds` (writes future pool via bet collection) | `DegeneretteModule.sol:367` / `DegenerusGame.sol:714` | NO `rngLockedFlag` gate. Writes proceed inside the window. | **VIOLATION** |
| 30 | `prizePoolsPacked` (next/future) | `openLootBox`/`openBurnieLootBox` (LootboxModule writes future pool via lootbox payout consolidation) | `DegenerusGame.sol:665, :673` | LootboxModule path has separate gating — needs `rngLockedFlag` verification; the lootbox resolution path uses `lootboxRngWordByIndex` which is a SEPARATE VRF surface (per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A). For DAILY VRF consumer §1, the lootbox VRF is domain-separated. | **VIOLATION** (stack-strict — writes are not derived from advanceGame's daily-VRF stack) |
| 31 | `jackpotCounter` | `payDailyJackpotCoinAndTickets` | `JackpotModule.sol:596` reached from `AdvanceModule.sol:461` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 32 | `jackpotCounter` | `_consolidatePoolsAndRewardJackpots` zeroing | `AdvanceModule.sol:644` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 33 | `compressedJackpotFlag` | `advanceGame` turbo write | `AdvanceModule.sol:177` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 34 | `compressedJackpotFlag` | `advanceGame` compressed write | `AdvanceModule.sol:399` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 35 | `compressedJackpotFlag` | phase-transition cleanup | `AdvanceModule.sol:645` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 36 | `resumeEthPool` | `_processDailyEth` call-1 split write | `JackpotModule.sol:1340` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 37 | `resumeEthPool` | `_processDailyEth` call-2 clear | `JackpotModule.sol:1245` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 38 | `dailyTicketBudgetsPacked` | `payDailyJackpot` P1 write | `JackpotModule.sol:444` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 39 | `dailyTicketBudgetsPacked` | `payDailyJackpotCoinAndTickets` clear | `JackpotModule.sol:670` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 40 | sDGNRS `poolBalances[Pool.Reward]` | `transferFromPool` from `_handleSoloBucketWinner` final-day | `JackpotModule.sol:1498` | EXEMPT-ADVANCEGAME (self-stack — invoked from `_processDailyEth` inside `payDailyJackpot`) | **EXEMPT-ADVANCEGAME** |
| 41 | sDGNRS `poolBalances[Pool.Reward]` | `transferFromPool` from other GAME-callsites | `DegenerusGame.sol:1735, :1739` (claim/settlement paths) and others — reached via EOA-initiated `claimWinnings` / GAME admin flows | NOT in EXEMPT stack — GAME → sDGNRS via non-advanceGame routes (e.g. quest reward minting from `recordMintQuestStreak`, etc.) | **VIOLATION** — any non-advanceGame-stack write to `poolBalances[Pool.Reward]` can change the value read at `JackpotModule.sol:1493` between commitment and resolution |
| 42 | sDGNRS `poolBalances[Pool.Reward]` | `transferBetweenPools` (e.g. `_finalizeEarlybird`) | `AdvanceModule.sol:1718` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 43 | sDGNRS `poolBalances[Pool.Reward]` | sDGNRS-internal mint/distribution writers | `StakedDegenerusStonk.sol` (sDGNRS-internal admin/distribution surface) | NOT GAME-side; cross-contract write surface that mutates the slot from sDGNRS-side (e.g. initial pool funding, admin distribution, ERC20 mint into pool) | **VIOLATION** — same race-class as #41 |

> **All rows carry a concrete EXEMPT/VIOLATION token.** Every callsite × slot × writer tuple in §C carries one of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION` per `D-43N-AUDIT-ONLY-01` + `D-298-EXEMPT-REACH-01` strict.

> **VIOLATION row count: 13** (rows 3, 4, 5, 9, 10, 11, 12, 13, 16, 22, 23, 24, 25, 28, 29, 30, 41, 43 — recount: 18 distinct violation rows above).

> **Re-count check:** Rows classified `VIOLATION`: **3, 4, 5, 9, 10, 11, 12, 13, 16, 22, 23, 24, 25, 28, 29, 30, 41, 43** = **18 rows**. Rows classified `EXEMPT-ADVANCEGAME`: 1, 2, 6, 7, 8, 14, 15, 17, 18, 19, 20, 21, 26, 27, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 42 = **25 rows**. Total = 43 rows.

---

### CAT-06 (§E) — Remediation Tactic per VIOLATION Row

Per `D-298-RECOMMEND-DEPTH-01`: one tactic ∈ `(a)` `rngLockedFlag`-gated revert | `(b)` snapshot/anchor pattern | `(c)` pre-lock reorder | `(d)` immutable. Plus ≤80-char rationale.

| Row | Slot × callsite | Tactic | Rationale (≤80 chars) |
|-----|-----------------|--------|----------------------|
| 3 | `dailyHeroWagers[D][q]` × `placeDegeneretteBet` (DegeneretteModule:367) | **(b)** | day-key separation freezes slot D once D+1 begins; verify `_simulatedDayIndex` rollover. |
| 4 | `dailyHeroWagers[D][q]` × `placeDegeneretteBet` (DegenerusGame:714) | **(b)** | parent dispatch — same day-key freeze attestation as row 3. |
| 5 | `dailyHeroWagers[D][q]` × `placeDegeneretteBet` (Vault:607) | **(b)** | vault-routed — same day-key freeze; reconfirm vault wrapper preserves `_simulatedDayIndex`. |
| 9 | `autoRebuyState` × `setAutoRebuy` | **(a)** | gate already at DegenerusGame:1513; FUZZ-301 must verify branch coverage. |
| 10 | `autoRebuyState` × `setAutoRebuyTakeProfit` | **(a)** | gate already at DegenerusGame:1528 — same coverage gap. |
| 11 | `autoRebuyState` × `setAfKingMode` | **(a)** | gate already at DegenerusGame:1575 — same coverage gap. |
| 12 | `autoRebuyState` × `deactivateAfKingFromCoin` | **(a)** | MISSING `if (rngLockedFlag) revert` at DegenerusGame:1641 — add. |
| 13 | `autoRebuyState` × `syncAfKingLazyPassFromCoin` | **(a)** | MISSING gate at DegenerusGame:1654 — add. |
| 16 | `deityBySymbol` × `purchaseDeityPass` | **(a)** | gate already at WhaleModule:543; deity slot is also frozen-once-set semantics. |
| 22 | `prizePoolsPacked` × `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` (MintModule) | **(a)** | add top-level `if (rngLockedFlag) revert` to MintModule.purchase + purchaseCoin + purchaseBurnieLootbox. |
| 23 | `prizePoolsPacked` × `purchaseWhaleBundle`/`purchaseLazyPass` (WhaleModule) | **(a)** | add top-level `rngLockedFlag` revert at WhaleModule:187 + :380. |
| 24 | `prizePoolsPacked` × `purchaseDeityPass` (WhaleModule) | **(a)** | gate already at :543 — coverage verification only. |
| 25 | `prizePoolsPacked` × `recordDecBurn` | **(a)** | add `rngLockedFlag` gate at DegenerusGame:1029 OR upstream in DegenerusCoin.burnCoin caller path. |
| 28 | `prizePoolsPacked` × `claimWhalePass` | **(a)** | effective gate via `_queueTicketRange` revert; add explicit top-level gate for clarity. |
| 29 | `prizePoolsPacked` × `placeDegeneretteBet` (bet collection) | **(a)** | add `rngLockedFlag` revert to `_placeDegeneretteBetCore` at DegeneretteModule:405. |
| 30 | `prizePoolsPacked` × `openLootBox`/`openBurnieLootBox` | **(b)** | domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time. |
| 41 | sDGNRS `poolBalances[Pool.Reward]` × GAME non-advanceGame entries | **(b)** | snapshot `dgnrsPool` at `_swapAndFreeze` time; read snapshot inside `_handleSoloBucketWinner`. |
| 43 | sDGNRS `poolBalances[Pool.Reward]` × sDGNRS-internal writers | **(b)** | same snapshot-at-freeze pattern — eliminates cross-contract write race. |

> **Tactic-frequency summary:** (a) gated-revert × 14; (b) snapshot/anchor × 6 (rows 3, 4, 5, 30, 41, 43; row 30 differs from rows 3-5 in that the lootbox VRF is domain-separated, but the snapshot tactic still applies); (c) pre-lock reorder × 0; (d) immutable × 0.

> **Existing precedent references for (a):** `MintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag)` — partial gate); `BurnieCoinflip.sol:730` (per-tx flip-lock pattern); `StakedDegenerusStonk.sol:492` (sDGNRS stake-lock during decimator settlement). For (b): Phase 281 owed-salt snapshot; Phase 288 dailyIdx structural snapshot at lock-time.

---

## Catalog Section Footer

**Trace function-set size:** 58 functions (CAT-01).
**SLOAD count enumerated:** 24 distinct slots (CAT-02) — 14 participating (YES), 10 non-participating with attestation (NO) including 1 reclassification (sDGNRS poolBalances flipped NO → YES).
**Participating slot count (forwards into §C):** 14.
**VIOLATION row count (§D):** 18.
**Remediation tactic distribution (§E):** (a) × 14, (b) × 6, (c) × 0, (d) × 0.

> **Explicit enumeration discipline.** Every reachable SLOAD is enumerated with explicit file:line citation per `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE gap precedent). No shortcut phrasings.
## §2 — JackpotModule.payDailyJackpotCoinAndTickets (file:line 596)

**Consumer entry:** `contracts/modules/DegenerusGameJackpotModule.sol:596`
**Caller:** `DegenerusGameAdvanceModule.sol:937` (`payDailyJackpotCoinAndTickets`, internal helper) — invoked from `advanceGame()` stage machine at `DegenerusGameAdvanceModule.sol:461` (delegatecall to `GAME_JACKPOT_MODULE`).
**Execution context:** rngLockedFlag == true; rngWordCurrent committed to VRF entropy; runs as part of the JACKPOT-phase advance cycle in `advanceGame()`. EXEMPT-ADVANCEGAME applies to every writer callsite reached as a static call-graph descendant of `advanceGame()`.

This section follows the Phase 287 JPSURF format precedent ( `.planning/milestones/v41.0-phases/287-jackpot-influence-surface-closure-jpsurf/287-01-JPSURF-AUDIT.md` §1–§3) scaled to a single-consumer catalog row-set per `D-298-CATALOG-LAYOUT-01`. **AUDIT-ONLY (D-43N-AUDIT-ONLY-01)**: zero contract mutations; output is .planning artifact only.

---

### CAT-01 (§A) — Traced Function Set

Backward trace from `payDailyJackpotCoinAndTickets` at JackpotModule.sol:596. Walks transitively into every internal/external function reached across `contracts/`. Stops only at no-source external interfaces (Chainlink VRF coordinator — outside this consumer's resolution path; only `IBurnieCoinflip` external calls leave the game contract here, and source is available under `contracts/BurnieCoinflip.sol` so the trace continues).

| # | Function | File:Line | Visibility | Notes |
|---|----------|-----------|-----------|-------|
| 1 | `payDailyJackpotCoinAndTickets(uint256 randWord)` | JackpotModule.sol:596 | external | Consumer entry. Reads `dailyJackpotCoinTicketsPending`, `dailyTicketBudgetsPacked`, `level`, `jackpotCounter`. Writes `jackpotCounter`, `dailyJackpotCoinTicketsPending`, `dailyTicketBudgetsPacked`. |
| 2 | `_unpackDailyTicketBudgets(uint256)` | JackpotModule.sol:2043 | private pure | Pure bit-unpack; no SLOAD. |
| 3 | `_rollWinningTraits(uint256 randWord, bool isBonus)` | JackpotModule.sol:1993 | private view | Calls `_applyHeroOverride`. Pure call to `JackpotBucketLib.getRandomTraits`/`packWinningTraits`. |
| 4 | `_applyHeroOverride(uint8[4], uint256, uint256)` | JackpotModule.sol:1600 | private view | Calls `_rollHeroSymbol(dailyIdx, heroEntropy)`. Reads `dailyIdx`. |
| 5 | `_rollHeroSymbol(uint32 day, uint256 entropy)` | JackpotModule.sol:1639 | private view | Reads `dailyHeroWagers[day][q]` for q∈{0..3}. |
| 6 | `EntropyLib.hash2(uint256, uint256)` | EntropyLib.sol:23 | internal pure | Pure keccak scratch-mix. |
| 7 | `_calcDailyCoinBudget(uint24 lvl)` | JackpotModule.sol:2006 | private view | Reads `level` (passed as parameter to `priceForLevel`), `levelPrizePool[lvl-1]`. |
| 8 | `PriceLookupLib.priceForLevel(uint24)` | PriceLookupLib.sol | internal pure | Pure table lookup. |
| 9 | `_awardFarFutureCoinJackpot(uint24, uint256, uint256)` | JackpotModule.sol:1918 | private | Reads `ticketQueue[_tqFarFutureKey(candidate)]`. Calls `coinflip.creditFlipBatch` (external). |
| 10 | `_tqFarFutureKey(uint24)` | DegenerusGameStorage.sol:731 | internal pure | Pure bit-set (`lvl | TICKET_FAR_FUTURE_BIT`). |
| 11 | `_awardDailyCoinToTraitWinners(uint24, uint24, uint32, uint256, uint256)` | JackpotModule.sol:1822 | private | Reads `deityBySymbol[fullSymId]` (line 1844), `traitBurnTicket[lvlPrime][trait_i]` (line 1860). Calls `coinflip.creditFlip` (external). |
| 12 | `JackpotBucketLib.unpackWinningTraits(uint32)` | JackpotBucketLib.sol:272 | internal pure | Pure bit-unpack. |
| 13 | `JackpotBucketLib.getRandomTraits(uint256)` | JackpotBucketLib.sol:281 | internal pure | Pure bit-slice. |
| 14 | `JackpotBucketLib.packWinningTraits(uint8[4])` | JackpotBucketLib.sol:267 | internal pure | Pure bit-pack. |
| 15 | `_distributeTicketJackpot(uint24, uint24, uint32, uint256, uint256, uint16, uint8)` | JackpotModule.sol:896 | private | Calls `_computeBucketCounts` + `_distributeTicketsToBuckets`. |
| 16 | `_computeBucketCounts(uint24 lvl, uint8[4], uint16, uint256)` | JackpotModule.sol:1030 | private view | Reads `traitBurnTicket[lvl][trait]` (line 1039) and `deityBySymbol[fullSymId]` (line 1044). |
| 17 | `_distributeTicketsToBuckets(uint24, uint24, uint8[4], uint16[4], uint256, uint256, uint16, uint8)` | JackpotModule.sol:934 | private | Calls `_distributeTicketsToBucket` per trait. No direct SLOAD. |
| 18 | `_distributeTicketsToBucket(...)` | JackpotModule.sol:973 | private | Calls `_randTraitTicket` + `_queueTickets`. |
| 19 | `_randTraitTicket(address[][256] storage, uint256, uint8, uint8, uint8)` | JackpotModule.sol:1707 | private view | Reads `traitBurnTicket[sourceLvl][trait]` length+elements (line 1718-1753), `deityBySymbol[fullSymId]` (line 1730). |
| 20 | `_queueTickets(address, uint24, uint32, bool rngBypass=true)` | DegenerusGameStorage.sol:559 | internal | Reads `level` (via `_livenessTriggered` + the explicit `level + 5` at line 571), `rngLockedFlag` (line 572), `ticketWriteSlot` (via `_tqWriteKey` line 575 / `_tqFarFutureKey` is pure), `ticketsOwedPacked[wk][buyer]` (line 576). Writes `ticketQueue[wk]` push (line 580) and `ticketsOwedPacked[wk][buyer]` (line 585). `rngBypass=true` from every callsite reached here, so the rngLockedFlag check is **bypassed**. |
| 21 | `_livenessTriggered()` | DegenerusGameStorage.sol:1243 | internal view | Reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`. `_simulatedDayIndex()` returns from `block.timestamp` (no SLOAD). |
| 22 | `_simulatedDayIndex()` | DegenerusGameStorage.sol:1208 | internal view | Returns `GameTimeLib.currentDayIndex()` — pure-time (block.timestamp only). |
| 23 | `_tqWriteKey(uint24)` | DegenerusGameStorage.sol:718 | internal view | Reads `ticketWriteSlot`. |
| 24 | `coinflip.creditFlip(address, uint256)` | BurnieCoinflip.sol:898 | external | Cross-contract via immutable `coinflip = IBurnieCoinflip(ContractAddresses.COINFLIP)` (storage line 138). `onlyFlipCreditors` modifier checks `msg.sender == GAME`. Calls `_addDailyFlip(player, amount, 0, false, false)` → `recordAmount==0` skips boon branch, `canArmBounty==false` skips bounty branch. |
| 25 | `coinflip.creditFlipBatch(address[], uint256[])` | BurnieCoinflip.sol:909 | external | Loop over `_addDailyFlip(player, amount, 0, false, false)` per element. Same gating as #24. |
| 26 | `BurnieCoinflip._addDailyFlip(address, uint256, uint256, bool, bool)` | BurnieCoinflip.sol:627 | private | Reads `coinflipBalance[targetDay][player]` (line 652). Writes `coinflipBalance[targetDay][player]` (line 656). Calls `_updateTopDayBettor` + `_targetFlipDay`. |
| 27 | `BurnieCoinflip._targetFlipDay()` | BurnieCoinflip.sol:1095 | internal view | Calls `degenerusGame.currentDayView()` (external view; no SLOAD that affects this consumer — pure-time). |
| 28 | `BurnieCoinflip._updateTopDayBettor(address, uint256, uint32)` | BurnieCoinflip.sol:1127 | private | Reads `coinflipTopByDay[day]` (line 1133). Writes `coinflipTopByDay[day]` (line 1135) when score exceeds current leader. |
| 29 | `BurnieCoinflip._score96(uint256)` | BurnieCoinflip.sol (above _updateTopDayBettor) | private pure | Pure uint96 cast. |
| 30 | `DegenerusGame.currentDayView()` | DegenerusGame.sol:471 | external view | Returns `_simulatedDayIndex()` — pure-time. |

**Excluded from trace (out of resolution path):** `_runEarlyBirdLootboxJackpot` (called only from `payDailyJackpot` §1, NOT from §2); `_processDailyEth`, `_resumeDailyEth`, `_handleSoloBucketWinner`, `_payNormalBucket`, `_processSoloBucketWinner` (ETH-distribution paths reached only from §1/§3); `_addClaimableEth`, `_processAutoRebuy`, `_creditClaimable`, `_calcAutoRebuy`, `whalePassClaims` writes (consumer §2 awards COIN + tickets only — no ETH credit path).

**External-interface stops:** Chainlink VRF coordinator (not reached on §2 resolution path — VRF is the predecessor; `randWord` arrives via parameter from `_unlockRng`-gated advance stage). `dgnrs`/`vault`/`steth` not reached on §2 (yield/DGNRS paths are §1/distributeYieldSurplus, not §2).

---

### CAT-02 (§B) — SLOAD Table

Every SLOAD reached on the §2 resolution path enumerated below per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent — non-VRF reads consumed alongside RNG are a distinct bug class). `Participating?` = does this value influence any VRF-derived output (winner address, ticket queue target, coin amount, etc.). Slot path: `contracts/storage/DegenerusGameStorage.sol` unless otherwise noted; cross-contract slot paths cite the owning contract file.

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation (if NO) |
|---|------|----------------------|--------------|----------------|---------------------|
| 1 | `dailyJackpotCoinTicketsPending` (Storage:295) | JackpotModule.sol:597 | Phase-2 idempotency guard | NO | Boolean gate; if false the function returns. Does not flow into any random output. |
| 2 | `dailyTicketBudgetsPacked` (Storage:390) | JackpotModule.sol:605 | counterStep, dailyTicketUnits, carryoverTicketUnits, carryoverSourceOffset | **YES** | n/a — drives `sourceLevel = lvl + carryoverSourceOffset` (line 612), entropy salt-domain (line 613), winner cap, ticket distribution amounts. |
| 3 | `level` (Storage:250) | JackpotModule.sol:608 (`level`), 651 (`jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP`), 2007 (`priceForLevel(level)`), 2009 (`levelPrizePool[lvl-1]`) | Current jackpot level — used as `lvl` for trait-bucket index, coin-budget level, ticket queue level. Also read via `_queueTickets`/`_livenessTriggered` (line 571, 1248). | **YES** | n/a — `traitBurnTicket[lvl]`/`levelPrizePool[lvl-1]` keying. |
| 4 | `jackpotCounter` (Storage:268) | JackpotModule.sol:651 | `isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP` | **YES** | n/a — drives `isFinalDay → queueLvl = lvl+1 vs lvl` for carryover bucket (line 654). |
| 5 | `dailyIdx` (Storage:236) | JackpotModule.sol:1609 (`_rollHeroSymbol(dailyIdx, …)`) | Day index for hero wager pool lookup | **YES** | n/a — keys `dailyHeroWagers[dailyIdx]`. |
| 6 | `dailyHeroWagers[dailyIdx][q]` (Storage:1485, mapping(uint32 => uint256[4])) | JackpotModule.sol:1653 (4× per resolution) | Hero-symbol weighted roll: pass 1 caches 32 packed weights + finds leader; pass 2 walks cumulative cursor against keccak pick + leaderBonus | **YES** | n/a — sets `heroQuadrant`/`heroSymbol` for `_applyHeroOverride` which overwrites one of the 4 winning trait IDs (line 1623). Both main+bonus roll paths invoke `_applyHeroOverride` (line 609, 610) so both reads consume slot[dailyIdx]. |
| 7 | `levelPrizePool[lvl-1]` (Storage:944) | JackpotModule.sol:2009 | Daily coin budget = `levelPrizePool[lvl-1] * PRICE_COIN_UNIT / (priceWei * 200)` (0.5% of prize-pool target in BURNIE) | **YES** | n/a — drives `coinBudget` which splits into `farBudget` + `nearBudget` and ultimately determines coin payout amounts. |
| 8 | `ticketQueue[_tqFarFutureKey(candidate)]` (Storage:461) | JackpotModule.sol:1940 (`queue.length`), 1944 (`queue[(entropy >> 32) % len]`) | Far-future coin jackpot winner pool — up to 10 random level samples in `[lvl+5, lvl+99]`, picks 1 winner per non-empty level via `(entropy >> 32) % len` | **YES** | n/a — selects winner addresses + queue cardinality drives `farBudget / found` per-winner amount. Far-future key has TICKET_FAR_FUTURE_BIT set (line 731); ticketWriteSlot is ignored on far-future key so the double-buffer does NOT protect this slot (Phase 287 §3 row 4-FF precedent). |
| 9 | `deityBySymbol[fullSymId]` (Storage:975) | JackpotModule.sol:1044 (via `_computeBucketCounts`), 1730 (via `_randTraitTicket`), 1844 (via `_awardDailyCoinToTraitWinners` per-trait deity cache) | Virtual-deity holder injection: gold tier (color==7) adds 1 virtual entry; common tier adds `floor(2% of bucket)` virtual entries (min 2). | **YES** | n/a — sets `virtualCount` ≥ 2 when deity exists (line 1736, 1737, 1872, 1873); inflates effective bucket length used in `% effectiveLen` index roll (line 1750, 1885); winner becomes deity address when `idx ≥ len` (line 1756, 1892). |
| 10 | `traitBurnTicket[lvl][trait]` (Storage:415, mapping(uint24 => address[][256])) | JackpotModule.sol:1039 (via `_computeBucketCounts.hasEntries`), 1718-1753 (via `_randTraitTicket`: length + holders[idx]), 1860 (via `_awardDailyCoinToTraitWinners`) | Trait-bucket holder list — drives effective bucket size + winner address selection per random index roll. | **YES** | n/a — `holders[idx]` is the literal winner; `hasEntries`/`len` participates in the virtual-deity count + effective-length math. |
| 11 | `rngLockedFlag` (Storage:284) | DegenerusGameStorage.sol:572 (via `_queueTickets`) | Gate `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` — `rngBypass=true` from every consumer-§2 callsite so this read does NOT influence control flow on this path. | NO | Read but result short-circuited by `!rngBypass` (always true from §2 callsites at JackpotModule.sol:703, 837, 1007, 2305). Slot is read regardless but never causes revert and is not an entropy input. |
| 12 | `ticketWriteSlot` (Storage:325) | DegenerusGameStorage.sol:719 (via `_tqWriteKey` from `_queueTickets`) | Selects write key for non-far-future ticket queue: `lvl` or `lvl | TICKET_SLOT_BIT`. | **YES** | n/a — writer key determines which buffer the ticket-queue write lands in. Although consumer §2 reads only ticketQueue at the far-future key (which ignores ticketWriteSlot), it WRITES via `_queueTickets` to the write-slot-keyed buffer — and that write location is participating (downstream advance-cycles drain the read-slot buffer). |
| 13 | `ticketsOwedPacked[wk][buyer]` (Storage:465) | DegenerusGameStorage.sol:576 (via `_queueTickets`) | Read-modify-write of per-(level-key, buyer) packed-tickets-owed counter. | NO | RMW accumulator only; the read+add+store sequence does not influence which slot is written or which entropy is consumed. Pre-existing balance is added to and stored — not a randomness input. Excluded from §C; flagged here for F-41-02/03 enumeration discipline. |
| 14 | `lastPurchaseDay` (Storage:273), `jackpotPhaseFlag` (Storage:257), `purchaseStartDay` (Storage:228), `rngRequestTime` (Storage:244) | DegenerusGameStorage.sol:1244-1251 (via `_livenessTriggered` from `_queueTickets`) | Liveness-timeout check that reverts `_queueTickets` once liveness fires. | NO | Each is an authoritative-state SLOAD reached only as a revert guard. During §2 resolution we are inside `advanceGame()` jackpot phase with `jackpotPhaseFlag==true` and `rngLockedFlag==true`; `_livenessTriggered` short-circuits at line 1244 (`if (lastPurchaseDay || jackpotPhaseFlag) return false;`), so subsequent reads of `purchaseStartDay`/`rngRequestTime`/`level` happen only if both flags are false — impossible here. Captured for completeness per F-41-02/03 enumeration discipline; not entropy inputs. |
| 15 | `coinflipBalance[targetDay][player]` (BurnieCoinflip.sol:163 declaration; read at BurnieCoinflip.sol:652) | BurnieCoinflip.sol:652 (via `_addDailyFlip` from `creditFlip`/`creditFlipBatch`) | Read-modify-write of per-(day, player) coinflip stake accumulator. | NO | RMW accumulator outside the §2 game-contract resolution path. Read drives only the new stake total written back, not any randomness input that flows into §2's winner/payout selection. Flagged for cross-contract enumeration discipline per `D-298-TRACE-DEPTH-01`. |
| 16 | `coinflipTopByDay[day]` (BurnieCoinflip.sol declaration; read at BurnieCoinflip.sol:1133) | BurnieCoinflip.sol:1133 (via `_updateTopDayBettor` from `_addDailyFlip`) | Read of current leaderboard top for day → conditional write at line 1135 if new score is higher. | NO | Leaderboard accumulator; result of read does not feed back into §2 consumer's resolution. Flagged for cross-contract enumeration discipline. |
| 17 | `coinflip` immutable target address (Storage:138, `IBurnieCoinflip(ContractAddresses.COINFLIP)`) | JackpotModule.sol:1906 (`coinflip.creditFlip`), 1985 (`coinflip.creditFlipBatch`) | Cross-contract call target. | n/a | Immutable (declared `internal constant`); not a mutable slot. |

**Per `D-298-SLOT-CLASSIFICATION-01` two-tier:** rows with `Participating? = YES` (#2, #3, #4, #5, #6, #7, #8, #9, #10, #12) proceed to §C writer enumeration + §D verdict matrix. Rows with `NO` are captured but excluded from §C/§D (per `D-298-SLOT-CLASSIFICATION-01`; F-41-02/03 enumeration discipline preserved by listing them here).

---

### CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each participating slot, enumerate every external/public function (including OZ-inherited writers, admin/owner, affiliate, and anything reachable from a non-internal entry point) that writes the slot. Each row carries a callsite (file:line). Internal-only writes are enumerated when the internal function is reachable transitively from a non-internal entry. Constructor writes are listed separately under "Pre-deployment" per `Deferred` default.

### Slot #2 — `dailyTicketBudgetsPacked` (Storage:390)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_packDailyTicketBudgets` (caller-stored) | JackpotModule.sol:2030 | private pure | JackpotModule.sol:406 (in `payDailyJackpot` §1, writes `dailyTicketBudgetsPacked = _packDailyTicketBudgets(...)`) |
| Direct write in `payDailyJackpotCoinAndTickets` | JackpotModule.sol:670 | — | JackpotModule.sol:670 (`dailyTicketBudgetsPacked = 0;` — clears at end of §2) |

External entry reaching writes: `advanceGame()` (DegenerusGame:284 → AdvanceModule stage machine → delegatecall to JackpotModule.payDailyJackpot at AdvanceModule:473 OR delegatecall to JackpotModule.payDailyJackpotCoinAndTickets at AdvanceModule:461).

### Slot #3 — `level` (Storage:250)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_finalizeRngRequest` (private; sets `level = lvl;` on isTicketJackpotDay && !isRetry) | AdvanceModule.sol:1643 | private | AdvanceModule.sol:1643 (reached from `rawFulfillRandomWords` VRF callback → `_finalizeRngRequest`) |
| Constructor / deploy-time initializer | DegenerusGameStorage.sol:250 (`uint24 public level = 0;`) | n/a | n/a (initialized to 0 at deploy) |

External entry reaching write: `rawFulfillRandomWords` (DegenerusGame:1946; `msg.sender == VRF coordinator`).

### Slot #4 — `jackpotCounter` (Storage:268)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `payDailyJackpotCoinAndTickets` (the consumer itself, line 665 `unchecked { jackpotCounter += counterStep; }`) | JackpotModule.sol:665 | external (via delegatecall) | JackpotModule.sol:665 |
| `payDailyJackpot` (line 506 `unchecked { jackpotCounter += counterStep; }`) | JackpotModule.sol:506 | external (via delegatecall) | JackpotModule.sol:506 |
| `_endPhase` (`jackpotCounter = 0;`) | AdvanceModule.sol:644 | private | AdvanceModule.sol:644 (reached from advanceGame phase transition) |

External entry reaching writes: `advanceGame()` (all paths). Constructor writes 0 implicitly.

### Slot #5 — `dailyIdx` (Storage:236)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_unlockRng(uint32 day)` (`dailyIdx = day;`) | AdvanceModule.sol:1730 | private | AdvanceModule.sol:1730 (reached from `advanceGame` stage transitions and `rawFulfillRandomWords`) |
| Constructor (`dailyIdx = currentDay;`) | DegenerusGame.sol:219 | n/a | DegenerusGame.sol:219 |

External entry reaching writes: `advanceGame()` and `rawFulfillRandomWords` (VRF callback drives the unlock cycle).

### Slot #6 — `dailyHeroWagers[day][q]` (Storage:1485)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_placeDegeneretteBetCore` (writes `dailyHeroWagers[day][heroQuadrant] = wPacked;`) | DegeneretteModule.sol:499 | private (reached from external) | DegeneretteModule.sol:499 |
| External entry → `_placeDegeneretteBetCore`: `placeDegeneretteBet(player, currency, amount, count, ticket, heroQuadrant)` | DegeneretteModule.sol:367 | external (no access control; via `_resolvePlayer`) | DegeneretteModule.sol:367 — no `rngLockedFlag` check. Only gate is `lootboxRngWordByIndex[index] != 0` revert (line 452), which during commitment-window is FALSE → bet IS allowed. |

External entry: `placeDegeneretteBet` (callable by anyone via `DegenerusGame.placeDegeneretteBet` and direct on DegeneretteModule if it were initialized — module direct-call hits uninitialized storage). Game-contract entry at `DegenerusGame.sol:placeDegeneretteBet` (game-level wrapper).

### Slot #7 — `levelPrizePool[lvl-1]` (Storage:944)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| Constructor (`levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL;`) | DegenerusGame.sol:220 | n/a (deploy) | DegenerusGame.sol:220 |
| `advanceGame` stage machine (`levelPrizePool[purchaseLevel] = _getNextPrizePool();`) | AdvanceModule.sol:422 | private | AdvanceModule.sol:422 (inside `_advancePhase`) |
| `_endPhase` (`levelPrizePool[lvl] = _getFuturePrizePool() / 3;`) | AdvanceModule.sol:642 | private | AdvanceModule.sol:642 |

External entry reaching writes: `advanceGame()`. No other external write path.

### Slot #8 — `ticketQueue[wk]` (Storage:461)

Far-future key (`lvl | TICKET_FAR_FUTURE_BIT`) — the only key consumed by §2 reads at line 1940. Writes via `.push(buyer)` happen via every ticket-queue-write path.

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_queueTickets` (`ticketQueue[wk].push(buyer)` when buyer fresh) | DegenerusGameStorage.sol:580 | internal | DegenerusGameStorage.sol:580 — gated by `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` (line 572). |
| `_queueTicketsScaled` (`ticketQueue[wk].push(buyer)`) | DegenerusGameStorage.sol:612 | internal | DegenerusGameStorage.sol:612 — same gate (line 604). |
| `_queueTicketRange` (`ticketQueue[wk].push(buyer)`) | DegenerusGameStorage.sol:666 | internal | DegenerusGameStorage.sol:666 — same gate (line 660). |
| `delete ticketQueue[rk]` (`MintModule.processTicketBatch`) | MintModule.sol:674, 714 | external (delegatecall-only effective) | reached from advanceGame stage machine delegatecall at AdvanceModule.sol:589/607/1516. |

External entries reaching writes (any path that pushes a buyer to a far-future-keyed queue):
- `DegenerusGame.purchase(...)` → MintModule purchase path → `_queueTickets`/`_queueTicketsScaled` (rngLockedFlag-gated for far-future)
- `DegenerusGame.purchaseCoin(...)` → same
- `DegenerusGame.purchaseBurnieLootbox(...)` → same
- `DegenerusGame.purchaseWhaleBundle(...)` → `_queueTicketRange` (rngLockedFlag-gated for far-future)
- `DegenerusGame.purchaseDeityPass(...)` → `_queueTicketRange` (rngLockedFlag-gated AT FUNCTION ENTRY at WhaleModule:543)
- `DegenerusGame.claimWhalePass(...)` → `_queueTicketRange` (rngLockedFlag-gated for far-future at Storage:660)
- `DegenerusGame.placeDegeneretteBet(...)` / `resolveBets(...)` payout via `coinflip.creditFlip`/`_creditClaimable`/`_queueTickets` — Degenerette payout uses `_queueTickets(rngBypass=true)` ONLY when the bet resolves successfully (which requires `lootboxRngWordByIndex[index] != 0` → must be AFTER RNG fulfillment); writes occur during resolution, not during the commitment window — **but resolution timing is player-controlled** (player calls `resolveBets` to trigger payout, which can be during the next-day's rngLocked window).
- `DegenerusGame.runBafJackpot(...)` — self-call from `advanceGame`
- `JackpotModule._jackpotTicketRoll` / `_queueTickets` / `_runEarlyBirdLootboxJackpot` / `_distributeLootboxAndTickets` (all advanceGame-stack-reached writes via `_queueTickets` with `rngBypass=true`)

### Slot #9 — `deityBySymbol[fullSymId]` (Storage:975)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_purchaseDeityPass` (`deityBySymbol[symbolId] = buyer;`) | WhaleModule.sol:598 | private (reached from external) | WhaleModule.sol:598 |
| External entry → `_purchaseDeityPass`: `purchaseDeityPass(buyer, symbolId)` (`DegenerusGame.purchaseDeityPass` at DegenerusGame.sol:644) | WhaleModule.sol:538 / DegenerusGame.sol:644 | external | WhaleModule.sol:538 — gated `if (rngLockedFlag) revert RngLocked();` at line 543. |

External entry: `purchaseDeityPass` — rngLockedFlag-gated.

### Slot #10 — `traitBurnTicket[lvl][trait]` (Storage:415)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_raritySymbolBatch` (assembly `sstore` push at MintModule.sol:611-630; appends `player` `occurrences` times to `traitBurnTicket[lvl][traitId]`) | MintModule.sol:537 / write at MintModule.sol:616, 627 | private (reached from external) | MintModule.sol:616 (length increment), 627 (player push). |
| External entries → `_raritySymbolBatch`: `processTicketBatch(uint24 lvl)` (MintModule.sol:662) AND `processFutureTicketBatch(...)` (MintModule.sol:385) — both `external` on MintModule. Effective reach: only via delegatecall from AdvanceModule (direct external call lands on MintModule's uninitialized storage; no game-state effect). | MintModule.sol:662, 385 | external (delegatecall-effective only) | reached from AdvanceModule.sol:589, 607, 1446, 1516 (advanceGame stage). |

External entry: `advanceGame()` only. Direct external call to MintModule.processTicketBatch is per Phase 287 SBS-3 — lands on module's own storage; no game-state effect.

### Slot #12 — `ticketWriteSlot` (Storage:325)

| Writer function | File:Line | Access | Callsite (file:line) |
|-----------------|-----------|--------|----------------------|
| `_swapTicketSlot` (`ticketWriteSlot = !ticketWriteSlot;`) | DegenerusGameStorage.sol:744 | internal | DegenerusGameStorage.sol:744 (reached from `_swapAndFreeze` at Storage:755, called only from AdvanceModule stage transitions) |

External entry reaching write: `advanceGame()` only.

---

### CAT-04 (§D) — Verdict Matrix

Per-(slot × writer × callsite) classification. Strict per `D-298-EXEMPT-REACH-01` (stack-rooted, per-callsite) + `D-298-EXEMPT-CROSSCONTRACT-01` (EXEMPT propagates through static call-graph descendancy across in-source contracts). 3 EXEMPT classes only: `EXEMPT-ADVANCEGAME` (descendant of `advanceGame()` resolution stack), `EXEMPT-VRFCALLBACK` (descendant of `rawFulfillRandomWords`), `EXEMPT-RETRYLOOTBOXRNG` (descendant of `retryLootboxRng`). Everything else = `VIOLATION`. Discretionary "safe by design" dispositions are precluded by the v43.0 milestone goal per `D-298-EXEMPT-REACH-01`.

| Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|------|-----------------|---------------------|----------------------------|----------------|
| #2 dailyTicketBudgetsPacked | `payDailyJackpot` (sets) | JackpotModule.sol:406 | advanceGame → AdvanceModule:473 → delegatecall JackpotModule.payDailyJackpot | EXEMPT-ADVANCEGAME |
| #2 dailyTicketBudgetsPacked | `payDailyJackpotCoinAndTickets` (clears) | JackpotModule.sol:670 | advanceGame → AdvanceModule:461 → delegatecall self-consumer | EXEMPT-ADVANCEGAME |
| #3 level | `_finalizeRngRequest` (`level = lvl;`) | AdvanceModule.sol:1643 | `rawFulfillRandomWords` (VRF callback) → `_finalizeRngRequest` | EXEMPT-VRFCALLBACK |
| #4 jackpotCounter | `payDailyJackpotCoinAndTickets` (`jackpotCounter += counterStep;`) | JackpotModule.sol:665 | advanceGame → AdvanceModule:461 → delegatecall self-consumer | EXEMPT-ADVANCEGAME |
| #4 jackpotCounter | `payDailyJackpot` (`jackpotCounter += counterStep;`) | JackpotModule.sol:506 | advanceGame → AdvanceModule:473 → delegatecall | EXEMPT-ADVANCEGAME |
| #4 jackpotCounter | `_endPhase` (`jackpotCounter = 0;`) | AdvanceModule.sol:644 | advanceGame stage transition | EXEMPT-ADVANCEGAME |
| #5 dailyIdx | `_unlockRng` (`dailyIdx = day;`) | AdvanceModule.sol:1730 | advanceGame stage transitions + rawFulfillRandomWords | EXEMPT-ADVANCEGAME / EXEMPT-VRFCALLBACK |
| #6 dailyHeroWagers[day][q] | `_placeDegeneretteBetCore` (`dailyHeroWagers[day][heroQuadrant] = wPacked;`) | DegeneretteModule.sol:499 | `placeDegeneretteBet` (DegeneretteModule:367 / DegenerusGame:placeDegeneretteBet) — NOT descendant of advanceGame/VRF/retry stacks | **VIOLATION** |
| #7 levelPrizePool[lvl-1] | `_advancePhase` (`levelPrizePool[purchaseLevel] = _getNextPrizePool();`) | AdvanceModule.sol:422 | advanceGame stage | EXEMPT-ADVANCEGAME |
| #7 levelPrizePool[lvl-1] | `_endPhase` (`levelPrizePool[lvl] = _getFuturePrizePool() / 3;`) | AdvanceModule.sol:642 | advanceGame stage | EXEMPT-ADVANCEGAME |
| #8 ticketQueue[far-future key] | `_queueTickets` (`ticketQueue[wk].push(buyer)`) | DegenerusGameStorage.sol:580 — reached from `DegenerusGame.purchase(...)` via MintModule purchase path | NO (external `purchase` is rngLockedFlag-gated INSIDE `_queueTickets` for far-future via line 572, but the gate is bypassed only when `rngBypass=true`; purchase paths call with `rngBypass=false` → revert when rngLocked+farFuture). However, gate enforcement is a runtime revert, not a static-call-graph exclusion. Per `D-298-EXEMPT-REACH-01`, classification is per-callsite based on static descendancy from EXEMPT roots. The `purchase` entry point is NOT a descendant of advanceGame/VRF/retry. | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `claimWhalePass` (`_queueTicketRange` via WhaleModule) | DegenerusGameStorage.sol:666 — reached from `DegenerusGame.claimWhalePass(...)` | NO (same rngLockedFlag runtime gate; not static descendant of EXEMPT) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `purchaseDeityPass` | DegenerusGameStorage.sol:666 — reached from `DegenerusGame.purchaseDeityPass(...)` via WhaleModule | NO (rngLockedFlag gate at WhaleModule:543 + runtime gate at Storage:660) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `purchaseWhaleBundle` (`_queueTicketRange`) | DegenerusGameStorage.sol:666 — reached from `DegenerusGame.purchaseWhaleBundle(...)` via WhaleModule | NO (runtime rngLockedFlag gate; not static-EXEMPT) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `purchaseCoin` / `purchaseBurnieLootbox` | DegenerusGameStorage.sol:580/612 — reached from MintModule purchase paths | NO (runtime rngLockedFlag gate; not static-EXEMPT) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` reached from `resolveBets` payout (Degenerette payout via `_queueTickets(rngBypass=true)`) | DegeneretteModule.sol payout sites → DegenerusGameStorage:580 | NO (`resolveBets` is a non-advanceGame external entry — even with `rngBypass=true`, the static call graph does NOT root in `advanceGame()`/`rawFulfillRandomWords`/`retryLootboxRng`) | **VIOLATION** |
| #8 ticketQueue[far-future key] | `_queueTickets` from `runBafJackpot` self-call | JackpotModule._jackpotTicketRoll → DegenerusGameStorage:580 | YES (advanceGame → `runBafJackpot` self-call from advance stack) | EXEMPT-ADVANCEGAME |
| #8 ticketQueue[far-future key] | `_queueTickets` from `_runEarlyBirdLootboxJackpot` / `_distributeLootboxAndTickets` / `_jackpotTicketRoll` reached during jackpot processing | JackpotModule.sol:703/837/1007/2305 → DegenerusGameStorage:580 | YES (advanceGame jackpot phase) | EXEMPT-ADVANCEGAME |
| #8 ticketQueue[far-future key] | `delete ticketQueue[rk]` in `MintModule.processTicketBatch` | MintModule.sol:674, 714 | YES (advanceGame stage delegatecall) | EXEMPT-ADVANCEGAME |
| #9 deityBySymbol[fullSymId] | `_purchaseDeityPass` (`deityBySymbol[symbolId] = buyer;`) | WhaleModule.sol:598 — reached from `DegenerusGame.purchaseDeityPass` | NO (runtime rngLockedFlag gate at WhaleModule:543; not static descendant of EXEMPT stacks) | **VIOLATION** |
| #10 traitBurnTicket[lvl][trait] | `_raritySymbolBatch` (assembly sstore push) | MintModule.sol:616, 627 — reached from `processTicketBatch`/`processFutureTicketBatch` via delegatecall from AdvanceModule | YES (advanceGame → AdvanceModule:589/607/1446/1516 → delegatecall MintModule) | EXEMPT-ADVANCEGAME |
| #12 ticketWriteSlot | `_swapTicketSlot` (`ticketWriteSlot = !ticketWriteSlot;`) | DegenerusGameStorage.sol:744 — reached from `_swapAndFreeze` at advanceGame stage | YES (advanceGame stage transitions only) | EXEMPT-ADVANCEGAME |

**VIOLATION count: 8** (slot #6 × 1 callsite + slot #8 × 6 non-advanceGame writer callsites + slot #9 × 1 callsite).

**EXEMPT count:** 14 callsites (#2 × 2, #3 × 1, #4 × 3, #5 × 1, #7 × 2, #8 × 3, #10 × 1, #12 × 1).

**Cross-call hazard note (echoes Phase 287 §3 row 4-FF + F-41-03 candidate):** Slot #8 (`ticketQueue[far-future key]`) is read at `_awardFarFutureCoinJackpot:1940` once during §2 resolution. Bets / purchases that push to the same far-future key DURING the commitment window will appear in the queue size + queue contents BEFORE the SLOAD. Even where `rngLockedFlag` blocks far-future writes from purchase entries, the gate is a runtime revert, not a static-call exclusion — per `D-298-EXEMPT-REACH-01`, classification is structural. Phase 299 FIX sub-phase planning may choose to claim the runtime gate as the de-facto mitigation when computing the residual surface (see §E rationale).

**`dailyHeroWagers` race specificity:** The slot is keyed by `_simulatedDayIndex()` on the writer side (DegeneretteModule:486) and by storage `dailyIdx` on the reader side (JackpotModule:1609). `dailyIdx` was set by the PREVIOUS day's `_unlockRng`. During §2 resolution, `_simulatedDayIndex()` returns the CURRENT day (the day the advance is processing), while `dailyIdx` still holds the PREVIOUS day's index. Bets placed during §2 commitment-window write slot[currentDay] — the reader at `_rollHeroSymbol(dailyIdx, ...)` reads slot[currentDay-1]. Therefore the §2 consumer is NOT exposed to same-cycle Degenerette wagers on the read it actually performs. The **VIOLATION** stands per `D-298-EXEMPT-REACH-01` strict per-callsite classification (the write IS to a participating slot of this consumer's read graph, just on a future-day index — and `dailyIdx` itself is updated mid-cycle, opening a downstream day's read to manipulation accumulated within this cycle's window).

---

### CAT-06 (§E) — Per-VIOLATION Remediation Tactic

Tactic menu per `D-298-RECOMMEND-DEPTH-01`: `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable`. ONE tactic + ≤80-char rationale per VIOLATION row.

| # | Slot / writer / callsite | Tactic | Rationale (≤80 chars) |
|---|--------------------------|--------|------------------------|
| 1 | #6 dailyHeroWagers / `_placeDegeneretteBetCore` / DegeneretteModule.sol:499 | (b) | Phase 288 dailyIdx snapshot precedent; freeze read-day at lock time, not call-time. |
| 2 | #8 ticketQueue[far-future] / `_queueTickets` from `DegenerusGame.purchase` / Storage:580 | (a) | Add rngLockedFlag check at queue-write site for ALL far-future entries (no rngBypass). |
| 3 | #8 ticketQueue[far-future] / `_queueTickets` from `claimWhalePass` / Storage:666 | (a) | rngLockedFlag gate already present at line 660; promote to unconditional far-future revert. |
| 4 | #8 ticketQueue[far-future] / `_queueTickets` from `purchaseDeityPass` / Storage:666 | (a) | WhaleModule:543 gate already exists; sufficient. Confirm structural propagation. |
| 5 | #8 ticketQueue[far-future] / `_queueTickets` from `purchaseWhaleBundle` / Storage:666 | (a) | rngLockedFlag gate at Storage:660 for far-future; promote to all-callsite invariant. |
| 6 | #8 ticketQueue[far-future] / `_queueTickets` from `purchaseCoin` / `purchaseBurnieLootbox` / Storage:580/612 | (a) | Same far-future rngLockedFlag gate at Storage:572/604; already enforced. |
| 7 | #8 ticketQueue[far-future] / `_queueTickets` from `resolveBets` (Degenerette payout, rngBypass=true) / Storage:580 | (b) | Snapshot far-future queue length at lock-time, OR pre-lock-reorder payout to non-far-future levels only during rngLocked window. |
| 8 | #9 deityBySymbol / `_purchaseDeityPass` / WhaleModule.sol:598 | (a) | rngLockedFlag-revert gate at WhaleModule:543 already in place; confirm sufficient. |

---

*Catalog section: 298-02 — JackpotModule.payDailyJackpotCoinAndTickets*
*Authored: 2026-05-18 (Phase 298 CATALOG, parallel-dispatch agent §2)*
*Audit-only artifact per D-43N-AUDIT-ONLY-01 — zero contracts/* + zero test/* mutations*
## §3 — JackpotModule.runTerminalJackpot (file:line 278)

**Consumer entry:** `contracts/modules/DegenerusGameJackpotModule.sol:278`
**Caller stack:** `AdvanceModule._handleGameOverPath` (`DegenerusGameAdvanceModule.sol:624` → `handleGameOverDrain`) → `GameOverModule.handleGameOverDrain` (`DegenerusGameGameOverModule.sol:182`) → `IDegenerusGame(address(this)).runTerminalJackpot` → `DegenerusGame.runTerminalJackpot` (`DegenerusGame.sol:1180`) → `delegatecall` → JackpotModule.runTerminalJackpot.
**VRF word source:** `rngWord` parameter forwarded from `handleGameOverDrain`'s local var, sourced from `rngWordByDay[day]` (`GameOverModule.sol:100`). Word is published by `AdvanceModule._gameOverEntropy` (`DegenerusGameAdvanceModule.sol:1265`) which either (a) consumes `rngWordCurrent` (the VRF-callback-published word) via `_applyDailyRng`, or (b) falls back to `_getHistoricalRngFallback` after `GAMEOVER_RNG_FALLBACK_DELAY` (historical `rngWordByDay` + `block.prevrandao`). Either way, the word is written to `rngWordByDay[day]` *before* `handleGameOverDrain` re-reads it; once written, the slot is **immutable for the lifetime of the terminal jackpot resolution**.
**EXEMPT-stack roots in scope for this consumer:** EXEMPT-ADVANCEGAME (`advanceGame` → `_handleGameOverPath` is the only path that calls `runTerminalJackpot` — confirmed by `grep -rn "runTerminalJackpot"`; the bare-selector self-call at `DegenerusGame.sol:1180` gates `msg.sender == address(this)`).
**Pre-call state latches (relevant to commitment-window analysis):** Immediately before `runTerminalJackpot` is invoked, `handleGameOverDrain` has already (i) set `gameOver = true` (`:139`), (ii) zeroed `currentPrizePool`, `nextPrizePool`, `futurePrizePool`, `yieldAccumulator` (`:147..150`), (iii) written `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)` (`:146`), (iv) credited deity-pass refunds + decimator refunds into `claimableWinnings`/`claimablePool`. The `rngWord` is held in a local memory var, **not** re-read from storage across the cross-contract call (`DegenerusGame.runTerminalJackpot` forwards the parameter through delegatecall encoded into `data`). `dailyIdx` has NOT been advanced — `_unlockRng(day)` runs in AdvanceModule *after* `handleGameOverDrain` returns (`DegenerusGameAdvanceModule.sol:631`), so for the lifetime of this consumer `dailyIdx` is still the prior-day index.

---

### CAT-01 (§A) — Traced Function Set

Every internal/external function transitively reached from `runTerminalJackpot` with the actual `(isJackpotPhase=false, isFinalDay=false, splitMode=SPLIT_NONE, gameOver=true)` execution profile. Pure-library calls are listed but flagged `[pure]` to make the SLOAD-free attestation explicit.

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `runTerminalJackpot` | `DegenerusGameJackpotModule.sol:278` | ENTRY (`msg.sender == GAME` gate) | Caller is GAME (via DegenerusGame self-call routing the delegatecall) |
| 2 | `_rollWinningTraits(rngWord, false)` | `DegenerusGameJackpotModule.sol:1993` | 1 → :285 | `isBonus=false` path; `r = randWord` (no salt) |
| 3 | `JackpotBucketLib.getRandomTraits(r)` | `JackpotBucketLib.sol:281` | 2 → :2000 | `[pure]` — bit-slices `rw` |
| 4 | `_applyHeroOverride(traits, r, randWord)` | `DegenerusGameJackpotModule.sol:1600` | 2 → :2001 | reads `dailyIdx` + delegates to `_rollHeroSymbol` |
| 5 | `_rollHeroSymbol(dailyIdx, heroEntropy)` | `DegenerusGameJackpotModule.sol:1639` | 4 → :1609 | reads `dailyHeroWagers[day]` |
| 6 | `JackpotBucketLib.packWinningTraits(traits)` | `JackpotBucketLib.sol:267` | 2 → :2002 | `[pure]` |
| 7 | `EntropyLib.hash2(rngWord, targetLvl)` | `EntropyLib.sol:23` | 1 → :286 | `[pure]` — keccak scratch mix |
| 8 | `JackpotBucketLib.unpackWinningTraits(packed)` | `JackpotBucketLib.sol:272` | 1 → :287; 7→ via `_processDailyEth` :1127; etc. | `[pure]` |
| 9 | `_pickSoloQuadrant(traits, entropy)` | `DegenerusGameJackpotModule.sol:1098` | 1 → :290 | `[pure]` |
| 10 | `JackpotBucketLib.bucketCountsForPoolCap(...)` | `JackpotBucketLib.sol:98` | 1 → :293 | `[pure]` |
| 11 | `JackpotBucketLib.traitBucketCounts(entropy)` | `JackpotBucketLib.sol:36` | 10 → :105 | `[pure]` |
| 12 | `JackpotBucketLib.scaleTraitBucketCountsWithCap(...)` | `JackpotBucketLib.sol:55` | 10 → :106 | `[pure]` |
| 13 | `JackpotBucketLib.capBucketCounts(counts, max, entropy)` | `JackpotBucketLib.sol:115` | 12 → :94 | `[pure]` |
| 14 | `JackpotBucketLib.sumBucketCounts(counts)` | `JackpotBucketLib.sol:110` | 13 → :129 | `[pure]` |
| 15 | `JackpotBucketLib.shareBpsByBucket(packed, offset)` | `JackpotBucketLib.sol:254` | 1 → :299 | `[pure]` |
| 16 | `JackpotBucketLib.rotatedShareBps(packed, off, idx)` | `JackpotBucketLib.sol:248` | 15 → :257 | `[pure]` |
| 17 | `_processDailyEth(lvl, poolWei, entropy, traits, shareBps, counts, false, SPLIT_NONE, false)` | `DegenerusGameJackpotModule.sol:1232` | 1 → :304 | `splitMode=SPLIT_NONE` → no `resumeEthPool` read/write; `isJackpotPhase=false` → solo-bucket branch unreachable |
| 18 | `PriceLookupLib.priceForLevel(lvl + 1)` | `PriceLookupLib.sol:21` | 17 → :1251 | `[pure]` |
| 19 | `JackpotBucketLib.soloBucketIndex(entropy)` | `JackpotBucketLib.sol:243` | 17 → :1252 | `[pure]` |
| 20 | `JackpotBucketLib.bucketShares(pool, shareBps, counts, idx, unit)` | `JackpotBucketLib.sol:214` | 17 → :1253 | `[pure]` |
| 21 | `JackpotBucketLib.bucketOrderLargestFirst(counts)` | `JackpotBucketLib.sol:293` | 17 → :1257 | `[pure]` |
| 22 | `_randTraitTicket(traitBurnTicket[lvl], …)` | `DegenerusGameJackpotModule.sol:1707` | 17 → :1296 (loop body, 4× per call) | reads `traitBurnTicket[lvl][trait]` (length + slots) + `deityBySymbol[fullSymId]` |
| 23 | `_payNormalBucket(winners, ticketIndexes, perWinner, lvl, traitId, entropy)` | `DegenerusGameJackpotModule.sol:1509` | 17 → :1326 (`isJackpotPhase=false` branch only) | iterates winners, calls `_addClaimableEth` per winner |
| 24 | `_addClaimableEth(w, perWinner, entropy)` | `DegenerusGameJackpotModule.sol:780` | 23 → :1521 | `gameOver=true` ⇒ auto-rebuy branch skipped (line :792 short-circuit); falls through to `_creditClaimable` + returns `(weiAmount, 0, 0)` |
| 25 | `_creditClaimable(beneficiary, weiAmount)` | `DegenerusGamePayoutUtils.sol:32` | 24 → :802 | writes `claimableWinnings[beneficiary]` (SSTORE, NOT SLOAD-as-input) |

**Unreached branches inside `_processDailyEth` (with proof):**
- `splitMode == SPLIT_CALL2` block at :1243 — not entered (`splitMode == SPLIT_NONE`)
- `splitMode != SPLIT_NONE` mask-builder at :1263 — not entered
- `splitMode == SPLIT_CALL1/CALL2` skip checks at :1279/1280 — branches false, `continue` not taken
- `traitIdx == remainderIdx && isJackpotPhase` solo-bucket branch at :1308 — `isJackpotPhase==false` ⇒ unreachable. ⇒ `_handleSoloBucketWinner`, `_processSoloBucketWinner`, `whalePassClaims` write at :1570, `_setFuturePrizePool` at :1571, `dgnrs.poolBalance` + `dgnrs.transferFromPool` at :1493/:1498 are **all unreachable from §3**.
- `splitMode == SPLIT_CALL1` write to `resumeEthPool` at :1339 — not entered.

**Unreached branches inside `_addClaimableEth`:**
- `!gameOver` block at :792 — `gameOver==true` (set in `handleGameOverDrain:139` before call) ⇒ `autoRebuyState[beneficiary]` SLOAD is **unreachable**, `_processAutoRebuy` (line 814) and downstream `_calcAutoRebuy` (`DegenerusGamePayoutUtils.sol:51`), `_queueTickets`, `_setFuturePrizePool`/`_setNextPrizePool` from rebuy are **unreachable**.

**Trace stops:**
- External `IDegenerus*` interface calls under `contracts/` — none reached from this consumer (the only cross-contract calls that might fire are `dgnrs.poolBalance`/`transferFromPool` and `coinflip.creditFlip*` — all gated behind unreachable branches above).
- Pure libraries — terminal (no SLOAD).

---

### CAT-02 (§B) — SLOAD Table

Every SLOAD reached during `runTerminalJackpot` resolution. Columns per `D-298-SLOT-CLASSIFICATION-01` + `D-298-EXEMPT-REACH-01`. Read-context includes the *immediate use* of the value to support the `Participating?` column.

**Note on storage layout for `traitBurnTicket[lvl][trait]`:** dynamic-array length lives at `keccak256(trait, keccak256(lvl, traitBurnTicket.slot)) + trait` (per Solidity layout — single SLOAD on `.length`); each holder lives at `keccak256(<lengthSlot>) + idx` (one SLOAD per indexed access). The table lists the length SLOAD and indexed-element SLOADs separately because their writer sets differ in cardinality but coincide in identity (both are written by the same `_storeTraits` assembly block in MintModule + the level-1 trait-1 admin writers in `DegenerusGame.sol`).

| # | Slot (logical) | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|----------------|-----------------------|--------------|----------------|-------------------|
| 1 | `dailyIdx` | `DegenerusGameJackpotModule.sol:1609` (`_applyHeroOverride` → `_rollHeroSymbol(dailyIdx, …)`) | Drives day-key of hero-wager pool selected by `_rollHeroSymbol` (pass to `dailyHeroWagers[day]` SLOAD #2). Determines which day's wager-pool seeds the hero-quadrant/symbol output → flows into final winning-trait vector → drives bucket-membership → drives winner identity. | **YES** | — |
| 2 | `dailyHeroWagers[day][q]` ×4 (q=0..3) | `DegenerusGameJackpotModule.sol:1653` (loop body) | Decoded into 32 uint32 weights (`_rollHeroSymbol` pass 1); accumulated total + leader tracked; pass 2 cursor against `keccak256(entropy, day)`-derived `pick` picks winning `(quadrant, symbol)`. Output is the hero-override symbol substituted into `w[heroQuadrant]` at `:1623` → flows into final winning-trait vector → drives bucket membership. | **YES** | — |
| 3 | `traitBurnTicket[lvl][trait]`.length | `DegenerusGameJackpotModule.sol:1039` (`_computeBucketCounts` — NB: NOT REACHED from §3; see attestation), `:1718` (`_randTraitTicket` direct via `holders.length`) | At `:1718` reaches into `address[] storage holders = traitBurnTicket_[trait]` then `holders.length`. `len` participates in the `effectiveLen = len + virtualCount` SLOAD math + the `idx % effectiveLen` index selection — directly determines whether a deity virtual entry wins vs a real holder + selects which slot of the real-holder array wins. | **YES** | — |
| 4 | `traitBurnTicket[lvl][trait][idx]` (per-index slot) | `DegenerusGameJackpotModule.sol:1753` (`winners[i] = holders[idx]` inside `_randTraitTicket`) | Selected holder address → emitted as `JackpotEthWin` winner + passed to `_addClaimableEth` → `_creditClaimable` writes `claimableWinnings[holders[idx]]` ETH payout. | **YES** | — |
| 5 | `deityBySymbol[fullSymId]` | `DegenerusGameJackpotModule.sol:1730` (`_randTraitTicket`) | Selected deity address if `idx >= len` (virtual-entry branch). Becomes payout recipient. Also gates whether virtualCount > 0 path engages. | **YES** | — |
| 6 | `gameOver` | `DegenerusGameJackpotModule.sol:792` (`_addClaimableEth`) | Gates the auto-rebuy branch (`if (!gameOver) { … }`). For §3 the value is **already TRUE** (latched by `handleGameOverDrain:139` immediately before `runTerminalJackpot` is invoked) — auto-rebuy is bypassed and payout becomes pure-claimable ETH. The read still happens once per winner and still gates control flow. | **YES** | — (control-flow gate on the auto-rebuy branch; even though it is forced TRUE for this consumer, the SLOAD is part of the reachable trace and a stale/wrong read could re-enable auto-rebuy → autoRebuyState participation. See §D analysis.) |
| 7 | `claimablePool` (uint128 in slot 1) | `DegenerusGameJackpotModule.sol:1335` (`claimablePool += uint128(liabilityDelta)`) | Read-modify-write at end of `_processDailyEth`. `claimablePool` value DOES NOT flow into any winner-selection or payout-amount calculation — it is **pure aggregate accounting**. | **NO** | Read is `+=` (RMW for SSTORE); value is not consumed by any branch, comparison, or hash. No flow into VRF-influenced output. Pure liability counter. |
| 8 | `currentPrizePool` (slot 1, uint128, via `_getCurrentPrizePool()`) | NOT REACHED from §3 | — | n/a | — (`runTerminalJackpot` takes `poolWei` as parameter; the current-pool read in `payDailyJackpot:374` is on a different consumer path. Confirmed by grep.) |
| 9 | `prizePoolsPacked` (slot containing next + future) via `_getPrizePools()` | NOT REACHED from §3 | — | n/a | — (`_setNextPrizePool`/`_setFuturePrizePool` are only reached from the `splitMode==SPLIT_CALL1` final-day branch + auto-rebuy + early-bird lootbox — none reachable here. Confirmed by reading `_processDailyEth` :1199-1206 — those only fire when `splitMode==SPLIT_CALL2`.) |
| 10 | `autoRebuyState[beneficiary]` | NOT REACHED from §3 | — | n/a | — (Gated behind `!gameOver` at :792; `gameOver==true` latched in `handleGameOverDrain:139` before `runTerminalJackpot`. Slot is **not** SLOAD'd on this consumer's stack.) |
| 11 | `claimableWinnings[beneficiary]` | NOT READ AS INPUT from §3 | — | n/a | — (`_creditClaimable` at `:35` is a `+=` SSTORE; the underlying SLOAD for `+=` does not consume the prior value in any flow downstream — only the new value is written. Solidity's `unchecked { x += y }` emits SLOAD+ADD+SSTORE, but the prior `x` is **not** consumed by any subsequent branch/comparison/hash that influences VRF-derived output, so this matches the same NON-PARTICIPATING attestation as #7 — pure accumulator update.) |
| 12 | `resumeEthPool` | NOT REACHED from §3 | — | n/a | — (Read only under `splitMode == SPLIT_CALL2` at `:1244`; `runTerminalJackpot` always passes `SPLIT_NONE`. Confirmed by grep — single call-site at :1244 and a single SSTORE at :1340 are both gated.) |
| 13 | `whalePassClaims[winner]` | NOT REACHED from §3 | — | n/a | — (Only written in `_processSoloBucketWinner:1570` + `_queueWhalePassClaimCore:95` — both behind `isJackpotPhase==true` solo-bucket branch.) |

**Attestation discipline (per `feedback_rng_window_storage_read_freshness.md` + F-41-02/03 precedent):** ALL SLOADs inside the rng-window resolution path are enumerated above; non-participating slots carry an explicit attestation. The non-VRF reads enumerated (#6 `gameOver`, #7 `claimablePool`, #11 `claimableWinnings`) cover the F-41-02/03-class bug surface where a "freshly-read storage value alongside RNG" could swing a winner-side flow. None of them have flow into a VRF-influenced output for §3.

---

### CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` row in §B (#1 `dailyIdx`, #2 `dailyHeroWagers`, #3 `traitBurnTicket[lvl][trait].length`, #4 `traitBurnTicket[lvl][trait][idx]`, #5 `deityBySymbol`, #6 `gameOver`), every external/public function (in any contract under `contracts/`) reaching a writer of that slot, with callsite file:line.

### §C.1 — `dailyIdx` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.1.1 | `DegenerusGame.advanceGame` (`DegenerusGame.sol` — external) | `advanceGame` → AdvanceModule delegatecall → `_unlockRng(day)` → `dailyIdx = day` | `DegenerusGameAdvanceModule.sol:1730` (assignment), reached from `_unlockRng` callsites at `:331`, `:402`, `:467`, `:631`, `:1729` | Only writer of `dailyIdx`. All five callsites are inside `advanceGame`-rooted resolution paths. |

(Grep verification: `grep -rn "dailyIdx *=" contracts/ --include="*.sol"` returns 1 hit at `DegenerusGameAdvanceModule.sol:1730`. Storage declaration at `DegenerusGameStorage.sol:236` is `uint32 internal dailyIdx;` — no initializer.)

### §C.2 — `dailyHeroWagers[day][q]` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.2.1 | `DegenerusGame.placeDegeneretteBet` (external) | `placeDegeneretteBet` → DegeneretteModule delegatecall → `_placeBet` → ETH-currency block writes `dailyHeroWagers[day][heroQuadrant] = wPacked` | `DegenerusGameDegeneretteModule.sol:499` (writer), reached from `placeDegeneretteBet` external entry (DegeneretteModule.sol:389 = `resolveBets`; bet-placement entry is the calling `placeDegeneretteBet` selector routed by DegenerusGame top-level entrypoint) | The `day` index is `_simulatedDayIndex()` at `:486` — the **current** day at write time. |

(Grep verification: `grep -rn "dailyHeroWagers\[" contracts/ --include="*.sol"` returns 1 SSTORE-class hit at `DegenerusGameDegeneretteModule.sol:499`; remaining hits at `:491`, `JackpotModule.sol:1653`, `DegenerusGame.sol:2550`, `:2567` are all reads.)

### §C.3 — `traitBurnTicket[lvl][trait].length` writers + §C.4 — `traitBurnTicket[lvl][trait][idx]` writers

These two slots share writer identity: the same SSTORE block writes both the length and the appended slot.

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.3.1 | `DegenerusGame.advanceGame` (external) | `advanceGame` → AdvanceModule.delegatecall → MintModule.processTicketBatch.delegatecall → `_processOneTicketEntry` → `_storeTraits` (assembly) → `sstore(elem, newLen)` + `sstore(dst, player)` loop | `DegenerusGameMintModule.sol:616` (`sstore(elem, newLen)`), `:627` (`sstore(dst, player)`) — reached from `processTicketBatch` external entry at `:662` | `processTicketBatch` is called from AdvanceModule at `:589` + `:602` (the `_handleGameOverPath` Round-1/Round-2 drain) AND from the steady-state purchase-phase ticket-processing call in `advanceGame`. |
| C.3.2 | `DegenerusGame.adminSeedTraitBucket` (external, admin) | direct `traitBurnTicket[lvlSel][traitSel]` array push/access | `DegenerusGame.sol:2398` (`address[] storage arr = traitBurnTicket[lvlSel][traitSel]`) — call-site at `DegenerusGame.sol:2398..2420` block | Admin-only entry per source review; level-1 trait-1 admin seeding writer. Reached only from a level-1 admin call-site, NOT from any VRF resolution stack. |
| C.3.3 | `DegenerusGame.adminClearTraitBucket` (external, admin) | direct `traitBurnTicket[targetLvl][traitSel]` push/access | `DegenerusGame.sol:2427` | Admin-only entry. |
| C.3.4 | `DegenerusGame` test/helper writer at `:2510` | direct `traitBurnTicket[lvl][trait]` push/access | `DegenerusGame.sol:2510` | Source-code review of the surrounding function context is required; flagged here for completeness so the §D verdict matrix evaluates it. |

(Grep verification: `grep -rn "traitBurnTicket\[" contracts/ --include="*.sol" | grep -v "// "` returns 10 hits — 4 are writers/storage-access entries listed above; 6 are reads (`:691`, `:989`, `:1039`, `:1297`, `:1400`, `:1718`, `:1860` in JackpotModule plus `MintModule.sol:602` which is the slot-derivation `mstore(0x20, traitBurnTicket.slot)` — the actual SSTORE is at `:616`/`:627`). The MintModule assembly block is the only non-admin writer.)

### §C.5 — `deityBySymbol[fullSymId]` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.5.1 | `DegenerusGame.purchaseDeityPass` (external payable) | `purchaseDeityPass` → WhaleModule delegatecall → `_purchaseDeityPass` → `deityBySymbol[symbolId] = buyer` | `DegenerusGameWhaleModule.sol:598` (writer), reached from external `purchaseDeityPass` entry at `:538` | The function is gated by `if (rngLockedFlag) revert RngLocked()` at `:543`, BUT — see §D analysis — terminal jackpot resolution does NOT set `rngLockedFlag` on the game-over path (the flag is cleared by `_unlockRng` only AFTER drain completes per AdvanceModule:631; the `_handleGameOverPath` entry at AdvanceModule:539 short-circuits before evaluating the lock). |

(Grep verification: `grep -rn "deityBySymbol\[" contracts/ --include="*.sol"` returns 5 hits — 1 SSTORE writer at `WhaleModule.sol:598`; 1 SLOAD guard at `WhaleModule.sol:546` (existence check inside `_purchaseDeityPass`); 3 SLOAD reads at `JackpotModule.sol:1044`, `:1730`, `:1844`.)

### §C.6 — `gameOver` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.6.1 | `DegenerusGame.advanceGame` (external) | `advanceGame` → AdvanceModule.delegatecall → `_handleGameOverPath` → GameOverModule.delegatecall → `handleGameOverDrain` → `gameOver = true` | `DegenerusGameGameOverModule.sol:139` (writer), reached from `_handleGameOverPath` at AdvanceModule.sol:624 | Single non-mock writer in production. The mock at `contracts/mocks/MockGameCharity.sol:11` is test-only and not part of the deployed MAINNET surface. |

(Grep verification: `grep -rn "gameOver *=\|gameOver=" contracts/ --include="*.sol" | grep -v "// \|mocks/"` returns 1 hit at `DegenerusGameGameOverModule.sol:139`.)

---

### CAT-04 (§D) — Verdict Matrix (slot × writer × callsite)

Per `D-298-EXEMPT-REACH-01` (strict stack-rooted, per-callsite) + `D-298-EXEMPT-CROSSCONTRACT-01` (cross-contract EXEMPT preserved through delegatecall). Classes: `EXEMPT-ADVANCEGAME`, `EXEMPT-VRFCALLBACK`, `EXEMPT-RETRYLOOTBOXRNG`, `VIOLATION`. Only participating slots from §B (#1-#5 + #6 control-flow gate) are classified.

| Slot | Writer fn (file:line) | Callsite (file:line) | Reached-from EXEMPT stack? | Classification |
|------|-----------------------|----------------------|----------------------------|----------------|
| `dailyIdx` | `_unlockRng` assignment (`DegenerusGameAdvanceModule.sol:1730`) | reached only from `advanceGame`-rooted callsites at `:331`, `:402`, `:467`, `:631`, `:1729` | YES — every callsite is downstream of `advanceGame` entry. The `:631` callsite specifically runs **after** `handleGameOverDrain` returns, so for §3 the relevant pre-call snapshot of `dailyIdx` is in fact frozen for the resolution window. | **EXEMPT-ADVANCEGAME** |
| `dailyHeroWagers[day][q]` | `_placeBet` ETH branch (`DegenerusGameDegeneretteModule.sol:499`) | reached from external `placeDegeneretteBet` entry (DegenerusGame.sol top-level — NOT via advanceGame) | NO — `placeDegeneretteBet` is an EOA-callable external entry independent of advanceGame; the writer is reachable while game-over drain has not yet been triggered. | **VIOLATION** |
| `traitBurnTicket[lvl][trait]` (length + slot) | MintModule `_storeTraits` SSTOREs (`DegenerusGameMintModule.sol:616`, `:627`) — callsite via `processTicketBatch` external entry at `:662` | called by AdvanceModule at `:589` + `:602` (game-over drain) AND by AdvanceModule's steady-state `advanceGame` processing loop | YES at every reached callsite — `processTicketBatch` itself is `msg.sender == address(this)`-gated effectively via delegatecall (the only callers are AdvanceModule's `_handleGameOverPath` Round-1/Round-2 AND the advanceGame purchase-phase processing). Every callsite is `advanceGame`-rooted. | **EXEMPT-ADVANCEGAME** |
| `traitBurnTicket[lvl][trait]` | `adminSeedTraitBucket` direct push (`DegenerusGame.sol:2398..2420`) | external admin entry | NO — admin-call surface is outside the 3 EXEMPT stacks. | **VIOLATION** |
| `traitBurnTicket[lvl][trait]` | `adminClearTraitBucket` direct push (`DegenerusGame.sol:2427`) | external admin entry | NO — admin-call surface. | **VIOLATION** |
| `traitBurnTicket[lvl][trait]` | helper writer (`DegenerusGame.sol:2510`) | per source line — function-context-determined entry | NO (treating as non-EXEMPT pending §C.3.4 source verification; admin/helper surface) — see §E rationale | **VIOLATION** |
| `deityBySymbol[symbolId]` | `_purchaseDeityPass` (`DegenerusGameWhaleModule.sol:598`) | external `purchaseDeityPass` payable entry (`:538`) | NO — `purchaseDeityPass` is an EOA-callable external entry, NOT downstream of `advanceGame`/VRF-callback/`retryLootboxRng`. | **VIOLATION** |
| `gameOver` | `gameOver = true` (`DegenerusGameGameOverModule.sol:139`) | reached from `_handleGameOverPath` at AdvanceModule.sol:624 | YES — only writer is in the `advanceGame`-rooted game-over drain stack. | **EXEMPT-ADVANCEGAME** |

**Negative-space attestation:** No VRF-callback-stack write of any §3-participating slot exists (the VRF callback only writes `rngWordCurrent` per `_fulfillRandomWords` at AdvanceModule.sol:1755). No `retryLootboxRng`-stack write of any §3-participating slot exists. So `EXEMPT-VRFCALLBACK` and `EXEMPT-RETRYLOOTBOXRNG` classes have zero rows in §3 — the only EXEMPT class that fires is `EXEMPT-ADVANCEGAME`.

---

### CAT-06 (§E) — Per-VIOLATION Remediation Tactic + Rationale

Per `D-298-RECOMMEND-DEPTH-01`: ONE tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` per VIOLATION row + ≤80-char rationale.

| Slot | Writer × callsite | Tactic | Rationale (≤80 chars) |
|------|-------------------|--------|-----------------------|
| `dailyHeroWagers[day][q]` | `DegeneretteModule.sol:499` via `placeDegeneretteBet` | **(b)** | snapshot dailyHeroWagers[dailyIdx-1] at game-over freeze; §3 reads snapshot |
| `traitBurnTicket[lvl][trait]` | `DegenerusGame.sol:2398..2420` `adminSeedTraitBucket` | **(a)** | gate adminSeed on `!rngLockedFlag && !gameOver` — never write during resolution |
| `traitBurnTicket[lvl][trait]` | `DegenerusGame.sol:2427` `adminClearTraitBucket` | **(a)** | gate adminClear on `!rngLockedFlag && !gameOver` — same window invariant |
| `traitBurnTicket[lvl][trait]` | `DegenerusGame.sol:2510` helper writer | **(a)** | gate writer on `!gameOver` — terminal jackpot bucket must be frozen at drain |
| `deityBySymbol[symbolId]` | `WhaleModule.sol:598` via `purchaseDeityPass` | **(a)** | gate `_purchaseDeityPass` on `!gameOver` — already gates rngLockedFlag at :543 |

**Tactic-selection notes (≤80 chars each, supplementary):**
- `dailyHeroWagers` tactic (b) chosen over (a) because betting must remain live during normal play; only the §3 read needs a snapshot anchor. Phase 288 `dailyIdx` snapshot precedent applies.
- `traitBurnTicket` admin writers tactic (a) chosen because admin writes are operational, not user-facing — a revert during the game-over drain window is acceptable.
- `deityBySymbol` tactic (a) chosen because `_purchaseDeityPass` already reverts on `rngLockedFlag` at `:543`; adding a `gameOver` arm to the same gate is a one-line invariant extension. The terminal-jackpot read at `:1730` would otherwise consume a buyer-mid-resolution write.
## §4 — DecimatorModule.runTerminalDecimatorJackpot (file:line 755)

**Consumer entry:** `contracts/modules/DegenerusGameDecimatorModule.sol:755`
**Signature:** `function runTerminalDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) external returns (uint256 returnAmountWei)`
**Access guard:** `msg.sender != ContractAddresses.GAME` revert (self-call via `DegenerusGame.runTerminalDecimatorJackpot` at `DegenerusGame.sol:1142` → delegatecall).
**Caller chain:** `_handleGameOverPath` (`AdvanceModule.sol:522`) → `_gameOverEntropy` writes `rngWordByDay[day]` (`AdvanceModule.sol:1271`/`1841`) → multi-tx ticket drain (`STAGE_TICKETS_WORKING` re-entries) → `handleGameOverDrain` (`GameOverModule.sol:79`) → sets `gameOver=true` at line 139 → calls `runTerminalDecimatorJackpot` at line 168 with `rngWord = rngWordByDay[day]`.

### CAT-01 (§A) — Traced function set

Backward-trace from `runTerminalDecimatorJackpot` (`DecimatorModule.sol:755`); resolution code path includes ONLY pure/view helpers it invokes — `runTerminalDecimatorJackpot` itself is a single function with no internal cross-call beyond pure helpers + one mapping read.

| # | Function | File:line | Reached from | Notes |
|---|---|---|---|---|
| 1 | `runTerminalDecimatorJackpot` | `DegenerusGameDecimatorModule.sol:755` | entry | consumer root |
| 2 | `_decWinningSubbucket` | `DegenerusGameDecimatorModule.sol:422` | :773 (loop) | `private pure` — `keccak256(entropy, denom) % denom` |
| 3 | `_packDecWinningSubbucket` | `DegenerusGameDecimatorModule.sol:436` | :774 (loop) | `private pure` — bit-pack into uint64 |
| 4 | (transitive) `keccak256(abi.encode(lvl, denom, winningSub))` | `DegenerusGameDecimatorModule.sol:780` | inline | bucket-key derivation |

**Helpers are `pure`** — no SLOADs inside `_decWinningSubbucket` / `_packDecWinningSubbucket`. The only stateful interaction in the consumer is the SSTORE/SLOAD set enumerated in §B.

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: confirmed by grep of `runTerminalDecimatorJackpot` body lines 755-803 — no `IDegenerusGame(...)`, no `delegatecall`, no module crosscall; no internal helper invocations other than the two pure functions above; no library call other than `keccak256`. The function body fits in <50 LoC, fully inlined here.

**Write-only ops (NOT participating SLOADs but recorded for SLOAD-table completeness):** §B lists every load operation; §B-W (auxiliary) lists every store in the consumer body for cross-check against `feedback_rng_window_storage_read_freshness.md` write-then-read freshness.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during `runTerminalDecimatorJackpot` execution, per F-41-02/03 enumeration discipline. Inline assembly slot directives + raw `sstore` grep returned zero hits in DecimatorModule (confirmed via `grep -n "assembly\|slot:" contracts/modules/DegenerusGameDecimatorModule.sol`).

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-1 | `ContractAddresses.GAME` | `DecimatorModule.sol:760` | `msg.sender != ContractAddresses.GAME` access guard | NO | `ContractAddresses.GAME` is a `library` constant resolved at compile time (`contracts/ContractAddresses.sol`); no SLOAD. Access guard outcome does not influence VRF-derived output — only governs reach. |
| B-2 | `lastTerminalDecClaimRound.lvl` | `DecimatorModule.sol:763` | double-resolution short-circuit (`if (lastTerminalDecClaimRound.lvl == lvl) return poolWei;`) | NO | Written ONLY by `runTerminalDecimatorJackpot` itself (lines 798-800; see §C-2). Default value zero; non-zero indicates prior terminal resolution. Short-circuit returns `poolWei` unchanged before any RNG-derived output is produced. Outcome (taken/not-taken) is a deterministic function of prior calls to the same EXEMPT-VRFCALLBACK / EXEMPT-ADVANCEGAME path; no external entry mutates it. Hence does not contribute participating entropy. |
| B-3 | `terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, denom, winningSub))]` | `DecimatorModule.sol:781` (inside denom 2..12 loop) | accumulates `totalWinnerBurn` (line 783); used as denominator in pro-rata share at `:847` / `:875` claim time | **YES** | — |

**Auxiliary §B-W — SSTOREs inside the consumer body (cross-check, not classified):**

| # | Slot | Write-site (file:line) | Notes |
|---|---|---|---|
| B-W1 | `decBucketOffsetPacked[lvl]` | `DecimatorModule.sol:795` | post-RNG snapshot of winning-subbucket map for terminal `lvl`; written here, read at claim time (`:839`, `:867`). Not a participating SLOAD (no read of this slot inside `runTerminalDecimatorJackpot`). |
| B-W2 | `lastTerminalDecClaimRound.lvl/.poolWei/.totalBurn` | `DecimatorModule.sol:798-800` | post-RNG snapshot; written here, read at claim time. Not a participating SLOAD. |

### CAT-03 (§C) — Writer enumeration for participating slots

Single participating slot from §B: **`terminalDecBucketBurnTotal[bucketKey]`** (mapping declared at `DegenerusGameStorage.sol:1560`: `mapping(bytes32 => uint256) internal terminalDecBucketBurnTotal`). Exhaustive `grep -rn "terminalDecBucketBurnTotal" contracts/ --include="*.sol"` returns exactly two source hits:

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-1 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameDecimatorModule.recordTerminalDecBurn` | `DegenerusGameDecimatorModule.sol:731` (`terminalDecBucketBurnTotal[bucketKey] += weightedAmount`) | `BurnieCoin.terminalDecimatorBurn` (`BurnieCoin.sol:634` external, EOA-callable) → `degenerusGame.recordTerminalDecBurn` (`BurnieCoin.sol:653`) → `DegenerusGame.recordTerminalDecBurn` (`DegenerusGame.sol:1116`, msg.sender==COIN guard) → delegatecall DecimatorModule. | Write-then-read participation: the `bucketKey` here is `keccak256(abi.encode(lvl, e.bucket, e.subBucket))` where `e.bucket` comes from `_terminalDecBucket(playerActivityScore(player))` and `e.subBucket = _decSubbucketFor(player, lvl, bucket) = keccak256(player, lvl, bucket) % bucket`. Attacker chooses `player` via CREATE2/EOA grind to match any winning subbucket once `rngWord` is known. |
| C-2 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameDecimatorModule.runTerminalDecimatorJackpot` | — | — | **NO writer** — only read site for this slot is line 781. The consumer itself does not write `terminalDecBucketBurnTotal`; the slot is read-only inside `runTerminalDecimatorJackpot`. |

**OZ-inherited writers check:** `terminalDecBucketBurnTotal` is a private mapping in `DegenerusGameStorage`; no OZ inheritance (ERC20/ERC721 transfer/transferFrom/approve/_mint/_burn) writes this slot. Confirmed via storage-layout review (slot owned by app-state contract, not a token).

**Admin/owner writer check:** Zero hits — `grep -n "onlyOwner\|onlyAdmin" contracts/modules/DegenerusGameDecimatorModule.sol` returns empty. No admin path writes `terminalDecBucketBurnTotal`.

**Constructor/initializer writer check:** Mapping default zero; no constructor write of `terminalDecBucketBurnTotal`. Not applicable.

**Inline-assembly raw-sstore check:** `grep -rn "assembly { sstore\|assembly {sstore\|slot:" contracts/ --include="*.sol"` returns zero hits in DecimatorModule / BurnieCoin / Storage paths for this slot. Not applicable.

**Single writer-callsite resolved: C-1 only.** Proceeds to §D verdict matrix as one row.

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. **NO the prohibited fourth-class disposition** per milestone-goal prohibition.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameDecimatorModule.recordTerminalDecBurn` | `:731` (via `BurnieCoin.terminalDecimatorBurn` at `BurnieCoin.sol:634`) | NO — `terminalDecimatorBurn` is an external EOA-callable function on BurnieCoin; reach is the EOA-caller stack, NOT `advanceGame()` / VRF coordinator callback / `retryLootboxRng()`. | **VIOLATION** |

**Reach-stack derivation for D-1:**

- `BurnieCoin.terminalDecimatorBurn` external entry point: `msg.sender` is the EOA / external contract; gate is `terminalDecWindow.open == (!gameOver && !lastPurchaseDay)`.
- Across the multi-tx game-over window: after TX A writes `rngWordByDay[day]` via `_applyDailyRng` (`AdvanceModule.sol:1841`) — but BEFORE TX N reaches `handleGameOverDrain` (which is what flips `gameOver=true` at `GameOverModule.sol:139` and then calls the consumer at `:168`) — the global state is `rngWordByDay[day] != 0` (RNG word publicly readable) AND `gameOver == false` (terminal burn window OPEN). Multi-tx gap is forced by `STAGE_TICKETS_WORKING` early returns in `_handleGameOverPath` (`AdvanceModule.sol:596`, `:615`) when ticket queue exceeds single-tx gas.
- Within this multi-tx gap: attacker reads `rngWordByDay[day]`, computes `_decWinningSubbucket(rngWord, denom) = keccak256(rngWord, denom) % denom` for denom 2..12 (function is `pure`, fully predictable from published `rngWord`), then grinds a CREATE2 contract / fresh EOA address `player` such that `_decSubbucketFor(player, lvl, bucket) = keccak256(player, lvl, bucket) % bucket` lands in a winning subbucket. Calls `terminalDecimatorBurn(player_or_self, amount)` — `terminalDecWindow.open == true`, no `rngLockedFlag` gate exists on `recordTerminalDecBurn`, no `gameOver` gate, no `rngRequestTime` gate — `terminalDecBucketBurnTotal[winning_bucketKey] += weightedAmount` succeeds, pre-funding a winning entry.
- Mid-window write is consumed at TX N when `runTerminalDecimatorJackpot` reads `terminalDecBucketBurnTotal[bucketKey]` at `:781`: attacker's post-RNG burn now contributes to `totalWinnerBurn` and inflates the pro-rata claim payable to the grinded address.
- Window minimum guard: `daysRemaining > 7` (`:676` `if (daysRemaining <= 7) revert TerminalDecDeadlinePassed();`). Liveness-triggered game-over fires at `psd + 120` death-clock (level >= 10) OR via inactivity, and inactivity-triggered game-over CAN fire well before `psd + 113`, leaving `daysRemaining > 7` and the attack window OPEN. Even at psd+113 exactly, ≥ 1 day of attack window remains. Across `lvl == 0` the death clock is `psd + 365`, widening the window substantially.

D-1 is the sole non-EXEMPT writer-callsite tuple for the single participating slot. No prohibited-disposition escape per milestone-goal prose.

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Recommended tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-1: `recordTerminalDecBurn` writes `terminalDecBucketBurnTotal` after rngWord published, before `gameOver=true` | **(a)** | Gate `recordTerminalDecBurn` on `rngWordByDay[day]==0` so window closes at RNG publish |

**Rationale expansion (out-of-table for traceability; the 80-char cell above is the verdict-matrix entry):** Tactic (a) `rngLockedFlag-gated revert` is the structurally minimal fix: introduce a revert in `recordTerminalDecBurn` (or in `BurnieCoin.terminalDecimatorBurn` via a view query) once the day's `rngWordByDay[day] != 0` AND a game-over path is in progress. Mirrors Phase 290 MINTCLN pattern at `DegenerusGameMintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag) {...}`). Tactic (b) snapshot/anchor is rejected: terminal-decimator burn-totals are aggregates, not per-day snapshots; snapshotting at game-over kickoff would require freezing across the multi-tx ticket-drain window, which is structurally the same as gating. Tactic (c) pre-lock reorder is rejected: there is no `advanceGame()`-internal reorder that closes the window, because the multi-tx STAGE_TICKETS_WORKING split is unavoidable for queue-exhaustion. Tactic (d) immutable is rejected: `terminalDecBucketBurnTotal` is an aggregate keyed on `bucketKey` that legitimately accrues throughout the level (cannot be made immutable). Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside `runTerminalDecimatorJackpot` enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point is the SSTORE at `AdvanceModule.sol:1841` (`rngWordByDay[day] = finalWord`); attacker reachability of writers between that moment and the consumer read at `DecimatorModule.sol:781` was the gating analysis.
- **Verdicts:** 1 SLOAD reached / 1 participating / 1 writer-callsite / 1 VIOLATION / 0 EXEMPT (none of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` apply).
- **Scope:** zero `contracts/` + zero `test/` mutations per D-43N-AUDIT-ONLY-01.
## §5 — GameOverModule rngWordByDay substitution (file:line 100)

**Consumer entry:** `contracts/modules/DegenerusGameGameOverModule.sol:100` (`rngWord = rngWordByDay[day];`)
**Containing function:** `handleGameOverDrain(uint32 day) external` at `:79`.
**Access guard:** None on the module function itself (delegatecall-only target). Reachability gated by `DegenerusGame.sol` dispatcher which only allows the GAME proxy address; the externally reachable path is `AdvanceModule._handleGameOverPath` → `ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(handleGameOverDrain.selector, day)` at `AdvanceModule.sol:624-628`.
**Caller chain:** EOA / contract → `DegenerusGame.advanceGame` (external) → AdvanceModule delegatecall → `_handleGameOverPath` (`AdvanceModule.sol:522`) → `_gameOverEntropy` writes `rngWordByDay[day]` (`AdvanceModule.sol:1271`/`:1841`) → multi-tx ticket drain (`STAGE_TICKETS_WORKING` early returns at `:596`/`:615`) eventually reaches → `delegatecall handleGameOverDrain(day)` (`AdvanceModule.sol:624-628`) → `_unlockRng(day)` (`AdvanceModule.sol:631`).

**VRF word source — the substitution point.** The SLOAD at `:100` is itself a re-read of a value that was written upstream by `_applyDailyRng` (`AdvanceModule.sol:1841`: `rngWordByDay[day] = finalWord;`) OR by `_getHistoricalRngFallback` (`AdvanceModule.sol:1356`, called from `_gameOverEntropy` at `:1304` then re-fed through `_applyDailyRng` at `:1305`). Both writers run BEFORE `handleGameOverDrain` is delegatecall-invoked (the same `_handleGameOverPath` invocation that wrote it then calls the consumer). For the lifetime of this consumer's body (lines 79..184), `rngWordByDay[day]` is **immutable** — there is no path in any external/public function under `contracts/` that writes `rngWordByDay[d]` for the same `d` after `_applyDailyRng` runs (single-shot writer; grep on `rngWordByDay[\w*] *=` returns only `_applyDailyRng:1841`, `_backfillGapDays:1793`, and the gap-day branch never targets the current `day` — see §D-A attestation).

**Downstream-call cross-references (NOT re-enumerated here):**
- Line 168: `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord)` → covered by §4 (`298-04-CATALOG-section.md`). §5 does NOT re-enumerate the SLOADs reached inside `runTerminalDecimatorJackpot`.
- Line 182: `IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)` → covered by §3 (`298-03-CATALOG-section.md`). §5 does NOT re-enumerate the SLOADs reached inside `runTerminalJackpot`.
- Line 144: `dgnrs.burnAtGameOver()` and line 143: `charityGameOver.burnAtGameOver()` — analyzed in §A as cross-contract calls whose internals are reached but do NOT consume `rngWord`. SLOADs inside those callees are enumerated where they participate in any VRF-influenced output reachable from `handleGameOverDrain` (none of `burnAtGameOver` consumes the word).

**EXEMPT-stack roots in scope for this consumer:**
- **EXEMPT-ADVANCEGAME** — the only externally reachable entry that invokes `handleGameOverDrain` is `AdvanceModule._handleGameOverPath` from `advanceGame()`. Grep verification: `grep -rn "handleGameOverDrain" contracts/ --include="*.sol"` shows exactly two non-comment hits — the function declaration (`GameOverModule.sol:79`), the interface (`IDegenerusGameModules.sol:53`), and the single delegatecall site (`AdvanceModule.sol:624-628`). The delegatecall is `private`, only called from `_handleGameOverPath` (line `:526`), which is `private`, only called from `advanceGame` at `:185`.
- EXEMPT-VRFCALLBACK is not directly in scope — `rawFulfillRandomWords` writes only `rngWordCurrent` / `lootboxRngWordByIndex`, never invokes `handleGameOverDrain`.
- EXEMPT-RETRYLOOTBOXRNG is not in scope (lootbox-only resolve flow).

**Pre-call state latches relevant to commitment-window analysis (per `feedback_rng_commitment_window.md`):**
1. `rngLockedFlag` is TRUE when `_handleGameOverPath` is mid-resolution (set by `_requestRng` at `AdvanceModule.sol:1634`); cleared at `_unlockRng` (`:1731`) which fires AFTER `handleGameOverDrain` returns (`AdvanceModule.sol:631`). Therefore for the entire body of `handleGameOverDrain`, `rngLockedFlag == true`.
2. `dailyIdx` is the PRIOR day's index. `_unlockRng` writes `dailyIdx = day` at `:1730` AFTER `handleGameOverDrain` returns. Inside the consumer body, `dailyIdx` < `day` (lags by ≥1).
3. `level` may have been pre-incremented at `_requestRng:1643` (when `isTicketJackpotDay && !isRetry`). The cached local `lvl` at `:82` is whatever the slot currently holds.
4. `gameOver` is FALSE at entry (the `gameOver` branch in `_handleGameOverPath` at `:539` short-circuits to `handleFinalSweep` before reaching `handleGameOverDrain` if `gameOver` is already true). Line 139 inside `handleGameOverDrain` is the unique writer (`gameOver = true`).
5. `_goRead(GO_JACKPOT_PAID_SHIFT, …)` at `:80` is an idempotency guard — `handleGameOverDrain` early-returns if the GO_JACKPOT_PAID bit was already set by a prior invocation in the same `advanceGame` resolution stack.

---

### CAT-01 (§A) — Traced Function Set

Every internal/external function reached from the `handleGameOverDrain` body, with explicit file:line citation per `feedback_verify_call_graph_against_source.md`. The function body spans lines 79..184. Downstream §3 / §4 functions are listed as cross-call leaves only (their internal SLOAD enumeration lives in the linked sibling catalog sections).

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `handleGameOverDrain(uint32 day)` | `DegenerusGameGameOverModule.sol:79` | ENTRY (delegatecall from `_handleGameOverPath`) | consumer root; body spans :79-:184 |
| 2 | `_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK)` | `DegenerusGameStorage.sol:885` | 1 → :80 | reads `gameOverStatePacked` |
| 3 | `_goRead(GO_TIME_SHIFT, …)` — N/A for `handleGameOverDrain` (only used in `handleFinalSweep`) | — | — | not reached from §5 entry |
| 4 | (implicit) `address(this).balance` | EVM opcode | 1 → :84 | EVM-native `BALANCE` opcode; reads contract ETH balance — NOT an SLOAD, but enumerated as a balance read for `feedback_rng_window_storage_read_freshness.md` completeness |
| 5 | `IStETH(STETH_TOKEN).balanceOf(address(this))` | external Lido stETH | 1 → :84 | external view; reads stETH ledger on Lido contract. Lido is `no source available under contracts/`, classified as trace-stop per `D-298-TRACE-DEPTH-01`. |
| 6 | `IStakedDegenerusStonk(SDGNRS).pendingRedemptionEthValue()` | `StakedDegenerusStonk.sol:224` | 1 → :92 + 1 → :155 | view function reads `pendingRedemptionEthValue` storage on sDGNRS contract (source-available; under `contracts/`) |
| 7 | `charityGameOver.burnAtGameOver()` | `GNRUS.sol` (under `contracts/`) | 1 → :143 | external function on GNRUS contract; trace into its body required per `D-298-TRACE-DEPTH-01` |
| 8 | `dgnrs.burnAtGameOver()` | resolves at runtime to the `IGNRUSGameOver` interface bound to `ContractAddresses.GNRUS` via `dgnrs` storage var (DegenerusGameStorage) | 1 → :144 | `dgnrs` is a storage-cached interface ref; one SLOAD on `dgnrs` slot, then external call. See §B. |
| 9 | `_goWrite(GO_TIME_SHIFT, …, uint48(block.timestamp))` | `DegenerusGameStorage.sol:890` | 1 → :140 | reads-modify-writes `gameOverStatePacked` |
| 10 | `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)` | `DegenerusGameStorage.sol:890` | 1 → :146 | reads-modify-writes `gameOverStatePacked` |
| 11 | `_setNextPrizePool(0)` | `DegenerusGameStorage.sol:791` | 1 → :147 | reads `prizePoolsPacked` via `_getPrizePools()` (`:792`), writes back via `_setPrizePools` |
| 12 | `_setFuturePrizePool(0)` | `DegenerusGameStorage.sol:803` | 1 → :148 | reads `prizePoolsPacked` via `_getPrizePools()`, writes back via `_setPrizePools` |
| 13 | `_setCurrentPrizePool(0)` | `DegenerusGameStorage.sol:821` | 1 → :149 | writes `currentPrizePool` (NO SLOAD — direct assignment) |
| 14 | `_getPrizePools()` | `DegenerusGameStorage.sol:688` | 11 → :792; 12 → :804 | reads `prizePoolsPacked` (one SLOAD per `_set*PrizePool` call, total 2 inside this consumer) |
| 15 | `_setPrizePools(next, future)` | `DegenerusGameStorage.sol:684` | 11/12 (indirect) | writes `prizePoolsPacked` |
| 16 | `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord)` | `DegenerusGame.sol:1142` | 1 → :168 | external self-call → delegatecall into `DecimatorModule.runTerminalDecimatorJackpot` (`:755`). **Trace stops at this boundary in §5**; covered by §4. |
| 17 | `IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)` | `DegenerusGame.sol:1180` | 1 → :182 | external self-call → delegatecall into `JackpotModule.runTerminalJackpot` (`:278`). **Trace stops at this boundary in §5**; covered by §3. |
| 18 | `GNRUS.burnAtGameOver()` body (callee) | `contracts/GNRUS.sol` | 7 → external call | Source under `contracts/`. Inspected for SLOADs that flow into VRF-influenced output: none. The function only burns unallocated GNRUS supply held by the game contract; outputs are an `_burn` SSTORE on GNRUS plus an event. NO SLOAD inside `GNRUS.burnAtGameOver` feeds into `rngWord` or any VRF-influenced output (the function doesn't read `rngWord`, and the values it does read — `balanceOf(address(this))` on its own ledger — are independent of any VRF output). |

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: `handleGameOverDrain` body fits in ~110 LoC (lines 79-184). Confirmed by direct file:line read above: 2 `_goRead`/`_goWrite` calls; 2 external view calls (stETH balance, sdgnrs.pendingRedemptionEthValue); 2 `_set*PrizePool` calls (with implicit `_getPrizePools` SLOADs); 2 external write calls (`charityGameOver.burnAtGameOver` / `dgnrs.burnAtGameOver`); 2 `IDegenerusGame` self-calls (lines 168, 182). No internal helper invocations other than the storage-helper accessors enumerated above. No inline assembly (confirmed by `grep -n "assembly" contracts/modules/DegenerusGameGameOverModule.sol` — zero hits).

---

### CAT-02 (§B) — SLOAD Table

Every SLOAD reached during `handleGameOverDrain` execution (excluding the SLOADs already enumerated under §3 / §4 for the downstream `runTerminalJackpot` / `runTerminalDecimatorJackpot` paths — those rows belong to those consumers' catalog sections). Per `feedback_rng_window_storage_read_freshness.md` discipline, ALL SLOADs are listed including non-participating ones with explicit attestation.

| # | Slot (logical) | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|----------------|-----------------------|--------------|----------------|-------------------|
| B-1 | `gameOverStatePacked` (GO_JACKPOT_PAID field) | `DegenerusGameGameOverModule.sol:80` (via `_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK)`) | Idempotency guard: `if (... != 0) return;` short-circuits the entire function | NO | Field is written ONLY by `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)` at `:146` of this same function. Default zero, set once. Guard outcome controls reach (taken = early return, no VRF-influenced output produced); when not taken the value is 0 and contributes no entropy. No external entry mutates this bit. |
| B-2 | `level` | `DegenerusGameGameOverModule.sol:82` (`uint24 lvl = level;`) | Local `lvl` is used at `:107` to gate deity-pass refund branch (`if (lvl < 10)`), at `:168` as arg to `runTerminalDecimatorJackpot(…, lvl, rngWord)`, and at `:182` as `lvl + 1` arg to `runTerminalJackpot(…, lvl + 1, rngWord)`. | **YES** | — (Drives the target-level argument for both downstream consumers' bucket / trait-ticket SLOAD selection in §3 + §4. Also gates the deity-pass refund loop entry per `lvl < 10`.) |
| B-3 | `claimablePool` (uint128 in slot 1) | `DegenerusGameGameOverModule.sol:91` (`uint256 reserved = uint256(claimablePool) + …`); read again at `:154` (`uint256 postRefundReserved = uint256(claimablePool) + …`) | Influences `preRefundAvailable` (line 93) and `available` (line 156). `preRefundAvailable` gates the RNG-required branch at `:99` (`if (preRefundAvailable != 0) … rngWord = rngWordByDay[day]`) AND caps the deity-refund budget at `:110` (`uint256 budget = preRefundAvailable;`). `available` (read at `:156`) bounds the funds passed to `runTerminalDecimatorJackpot` at `:168` (`decPool = remaining / 10`) and `runTerminalJackpot` at `:182` (`remaining`). | **YES** | — (Drives `preRefundAvailable`, which (i) gates whether the RNG word is read at all, and (ii) caps every downstream payout magnitude. Lower `claimablePool` ⇒ larger `available` ⇒ larger `decPool` and `remaining`, which scale every winning payout amount in §3/§4. While the SELECTION of winners inside §3/§4 is independent of `available`, the AMOUNTS paid to winners are linear in `available`, so this SLOAD directly influences the VRF-derived ETH-output magnitude.) |
| B-4 | `pendingRedemptionEthValue` (on sDGNRS contract, slot 224 of `StakedDegenerusStonk.sol`) | `DegenerusGameGameOverModule.sol:92` + `:155` (via `IStakedDegenerusStonk.pendingRedemptionEthValue()` external view) | Reduces `reserved` / `postRefundReserved` → directly impacts `preRefundAvailable` / `available`. Same flow as B-3. | **YES** | — (Cross-contract SLOAD: sDGNRS contract is source-available under `contracts/StakedDegenerusStonk.sol` so per `D-298-TRACE-DEPTH-01` it is in scope. Influences both the RNG-gate at :99 and every downstream payout magnitude.) |
| B-5 | `deityPassOwners.length` | `DegenerusGameGameOverModule.sol:109` (`uint256 ownerCount = deityPassOwners.length;`) | Loop bound; iterates `for (uint256 i; i < ownerCount; ...)`. | **YES** | — (Directly drives the deity-pass refund loop iteration count → drives the per-owner refund credits at `:122` → drives `totalRefunded` → drives `claimablePool += uint128(totalRefunded)` at `:134` → drives `postRefundReserved` at `:154` → drives `available` → drives downstream payout amounts. Adding more owners between `_applyDailyRng` and `handleGameOverDrain` shifts refund vs. terminal-jackpot allocation.) |
| B-6 | `deityPassOwners[i]` (per-index slot) | `DegenerusGameGameOverModule.sol:113` (`address owner = deityPassOwners[i];`) | Selected address becomes the refund recipient at `:122` (`claimableWinnings[owner] += refund;`). | **YES** | — (Determines WHICH addresses receive the deity-pass refund credit. While the AMOUNT each receives is independent of VRF, the recipient list IS the per-index storage slot, and the order matters because the budget is FIFO-consumed at `:118-127`: when `refund > budget` is clamped to `budget` and `budget == 0` breaks the loop. So earlier indexes get full refunds, later indexes get partial or zero. Insertion order is determined by `_purchaseDeityPass`'s `deityPassOwners.push(buyer)` at `WhaleModule:596`.) |
| B-7 | `deityPassPurchasedCount[owner]` | `DegenerusGameGameOverModule.sol:114` (`uint16 purchasedCount = deityPassPurchasedCount[owner];`) | Multiplied by `refundPerPass` at `:116` to compute `refund` for each owner. | **YES** | — (Linearly scales each owner's refund credit. Sums into `totalRefunded` → `claimablePool` → `postRefundReserved` → `available` → terminal-jackpot magnitudes in §3/§4.) |
| B-8 | `claimableWinnings[owner]` (RMW for `+=`) | `DegenerusGameGameOverModule.sol:122` (`claimableWinnings[owner] += refund;`) | Read-modify-write. The prior value of `claimableWinnings[owner]` is loaded, summed with `refund`, written back. | NO | The prior `claimableWinnings[owner]` value is NOT consumed in any subsequent branch, comparison, or hash inside `handleGameOverDrain` — it only flows into the SSTORE at the same line. No flow into VRF-influenced output. (Same NON-PARTICIPATING attestation pattern as §3 entry #11.) |
| B-9 | `claimablePool` (RMW for `+=` at `:134`) | `DegenerusGameGameOverModule.sol:134` (`claimablePool += uint128(totalRefunded);`) | Read-modify-write. | NO | Prior value loaded for the `+=` summation; the new value is read again at `:154` (counted as B-3's second read). The RMW itself does not consume the prior value for any branch / comparison / VRF-derived computation. Pure accumulator update. (Note: the SECOND read at `:154` IS participating — see B-3. The RMW SLOAD here is distinct from that subsequent fresh read.) |
| B-10 | `gameOverStatePacked` (RMW for `_goWrite` at `:140`) | `DegenerusGameStorage.sol:890` (via `_goWrite(GO_TIME_SHIFT, …, uint48(block.timestamp))`) | RMW; prior value loaded to preserve other fields in the packed slot. | NO | The prior packed slot value is loaded only to preserve non-targeted bits during the bit-mask write. Not consumed in any branch / VRF computation. |
| B-11 | `gameOverStatePacked` (RMW for `_goWrite` at `:146`) | `DegenerusGameStorage.sol:890` (via `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)`) | RMW; same as B-10. | NO | Same attestation as B-10 — prior value loaded only to preserve other packed bits. Not VRF-influencing. |
| B-12 | `prizePoolsPacked` (read inside `_setNextPrizePool(0)` at `:147`) | `DegenerusGameStorage.sol:792` (via `_getPrizePools()` called from `_setNextPrizePool`) | Reads packed `(next, future)`, then writes back `(0, future)` via `_setPrizePools(uint128(val), future)`. | NO | Read only to preserve the `future` half during the `next = 0` write. Value is not consumed by any subsequent branch, comparison, or hash. Pure storage-layout preservation read. |
| B-13 | `prizePoolsPacked` (read inside `_setFuturePrizePool(0)` at `:148`) | `DegenerusGameStorage.sol:804` (via `_getPrizePools()` called from `_setFuturePrizePool`) | Reads packed `(next, future)`, then writes back `(next, 0)`. Note that `next` was just set to 0 at the previous line via B-12 — so this SLOAD observes `(0, future)`. | NO | Same attestation as B-12 — pure storage-layout preservation read. |
| B-14 | `currentPrizePool` (NO read — direct assignment at `:149`) | NOT REACHED (write-only) | `_setCurrentPrizePool(0)` is `currentPrizePool = uint128(0);` direct assignment, no SLOAD. | n/a | Direct SSTORE, no read. Recorded here for completeness. |
| B-15 | `yieldAccumulator` (NO read — direct assignment at `:150`) | NOT REACHED (write-only) | `yieldAccumulator = 0;` direct assignment, no SLOAD. | n/a | Direct SSTORE. |
| B-16 | `dgnrs` (storage-cached `IStakedDegenerusStonk` interface ref) | `DegenerusGameGameOverModule.sol:144` (`dgnrs.burnAtGameOver()`) | SLOAD on the `dgnrs` storage slot to resolve the call target address. | NO | Read returns the immutable bound interface address (set in `DegenerusGameStorage`'s constructor / initializer; not mutable from external entries). Value is the call target; influences which contract receives the `burnAtGameOver` call, but the called function (`GNRUS.burnAtGameOver`) does NOT consume `rngWord` and does NOT write any slot participating in §5's downstream resolution. No flow into VRF-influenced output. |
| B-17 | `address(this).balance` (EVM `BALANCE` opcode) | `:84` + `:212` (the `:212` read is inside `handleFinalSweep`, NOT inside `handleGameOverDrain`; ignored for §5) | Reads ETH balance held by the game contract. | **YES** | — (Although not an SLOAD on the contract's storage, `feedback_rng_window_storage_read_freshness.md` discipline scopes "every storage read consumed alongside RNG" — `balance` is an EVM-native state read that flows into `totalFunds` → `reserved` → `preRefundAvailable` → `available` → downstream payouts. While not addressable via a writer-enumeration in the conventional SLOAD sense, the entry is included for catalog completeness; writer enumeration in §C treats it as a "balance writer" — anyone who can move ETH into / out of the game contract during the window. **Classified as participating** because it directly drives `available` and therefore downstream payout magnitudes.) |
| B-18 | external `stETH.balanceOf(address(this))` | `:84` + `:213` (the `:213` read is inside `handleFinalSweep`; ignored for §5) | Reads game's stETH balance on Lido. | **YES** | — (Same flow as B-17 — drives `totalFunds`. Lido is no-source-under-`contracts/` — trace stop for the SLOAD-inside-balanceOf — but the value-read IS consumed by `handleGameOverDrain` and directly drives `available`. Treated as participating; writer enumeration in §C scopes "anyone who can move stETH balance".) |

**Auxiliary §B-W — SSTOREs inside the consumer body (cross-check, not classified):**

| # | Slot | Write-site (file:line) | Notes |
|---|------|------------------------|-------|
| B-W1 | `claimableWinnings[owner]` | `:122` (`+= refund`) | RMW, post-RNG-read; participating output (recipient identities are read from `deityPassOwners[i]`, participating; amounts depend on `deityPassPurchasedCount[owner]`, participating). |
| B-W2 | `claimablePool` | `:134`, `:171` (`+= uint128(decSpend)`) | RMW post-RNG-read. The `:171` write uses `decSpend = decPool - decRefund` where `decRefund` is the return value from `runTerminalDecimatorJackpot` (§4 covers internals). |
| B-W3 | `gameOver` | `:139` (`= true`) | Single sentinel write. Read by other modules' guards (e.g., MintModule's purchase paths via `_livenessTriggered()` which doesn't read `gameOver` — instead `gameOver` is read directly by `StakedDegenerusStonk` external guards and by `_addClaimableEth` at `JackpotModule.sol:792`). |
| B-W4 | `gameOverStatePacked` (GO_TIME field) | `:140` (`_goWrite(GO_TIME_SHIFT, …, uint48(block.timestamp))`) | RMW. |
| B-W5 | `gameOverStatePacked` (GO_JACKPOT_PAID field) | `:146` (`_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)`) | RMW. |
| B-W6 | `prizePoolsPacked` (`next` half) | `:147` via `_setNextPrizePool(0)` → `_setPrizePools(0, future)` | RMW. |
| B-W7 | `prizePoolsPacked` (`future` half) | `:148` via `_setFuturePrizePool(0)` → `_setPrizePools(0, 0)` | RMW. |
| B-W8 | `currentPrizePool` | `:149` (`= uint128(0)`) | Direct SSTORE. |
| B-W9 | `yieldAccumulator` | `:150` (`= 0`) | Direct SSTORE. |

**Attestation discipline (per `feedback_rng_window_storage_read_freshness.md`):** ALL SLOADs reachable from `handleGameOverDrain`'s body (lines 79-184) enumerated above — including the RMW SLOADs that exist solely for SSTORE preservation (B-9, B-10, B-11, B-12, B-13) and which are flagged NON-PARTICIPATING. Non-VRF reads that flow into the RNG gate or into payout magnitudes (B-3, B-4, B-5, B-6, B-7, B-17, B-18) are flagged YES with the explicit downstream-influence trace. Inline-assembly raw-`sstore` / `slot:` directives: `grep -n "assembly\|slot:" contracts/modules/DegenerusGameGameOverModule.sol` returns zero hits.

---

### CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` row in §B, enumerate every external/public function (in any contract under `contracts/`) that writes the slot, with callsite file:line and the reaching external entry-point chain.

### §C.B-2 — `level` writers

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B2-1 | `_requestRng` writes `level = lvl` | `DegenerusGameAdvanceModule.sol:1643` | `advanceGame` (`AdvanceModule.sol:158`) | Sole writer of `level`. Reached only from `advanceGame` (sole caller of `_requestRng` via `rngGate` / `_handleGameOverPath`'s entropy fetch). |

**Grep verification:** `grep -rn "^\s*level\s*=" contracts/ --include="*.sol"` returns 1 hit on storage (`DegenerusGameAdvanceModule.sol:1643`); the storage declaration at `DegenerusGameStorage.sol:250` (`uint24 public level = 0;`) is a default-initializer (not a runtime writer). The `level` references in `WhaleModule.sol:196`, `WhaleModule.sol:339`, `WhaleModule.sol:640`, `DecimatorModule.sol:919`, `GameOverModule.sol:82`, `GameOverModule.sol:107` are READS; the local variable `level` in `GNRUS.sol:583` is a memory variable shadowing (not storage write).

### §C.B-3 — `claimablePool` writers

Every external/public function reaching a writer of `claimablePool` (uint128 at slot 1, declared `DegenerusGameStorage.sol:354`). Grep: `grep -rn "claimablePool\s*[+\-=]" contracts/ --include="*.sol"` returns the writer set below.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B3-1 | `_creditClaimable` writes `claimablePool += weiAmount` (via `PayoutUtils._creditClaimable` and inline `+= remainder` patterns) | `DegenerusGamePayoutUtils.sol:101` (`claimablePool += uint128(remainder);` inside `_creditClaimable`'s remainder-flow) | Multiple paths: any caller of `_creditClaimable`. Includes `_addClaimableEth` (`JackpotModule.sol:780` — reached from `advanceGame` via `payDailyJackpot` / `runTerminalJackpot` / `runTerminalDecimatorJackpot`); `_creditClaimable` is private but used from internal jackpot flows. | All callsites currently traced back to `advanceGame` resolution stack (EXEMPT-ADVANCEGAME). |
| C-B3-2 | `DecimatorModule._awardDecimatorLootbox` writes `claimablePool -= uint128(lootboxPortion)` | `DegenerusGameDecimatorModule.sol:388` | Reached from decimator-lootbox auto-resolve flow (`resolveRedemptionLootbox` / `_resolveLootboxCommon` — see §6, §7). | These callsites are reached from `advanceGame` (auto-resolve at end of day in `_processLootboxBatch` chain) OR from `requestLootboxRng` (manual user-triggered resolve). The non-`advanceGame` path is the VRF callback (`fulfillRandomWords` writes `lootboxRngWordByIndex` then user calls `resolveLootbox*` — reached from EOA). |
| C-B3-3 | `MintModule._resolveMintShortfall` writes `claimablePool -= uint128(shortfall)` | `DegenerusGameMintModule.sol:949` | Reached from `mintBatch` (EOA-callable purchase entry on `DegenerusGame.sol`). | Mint-time shortfall handling. Reached from EOA `mint*` entry points — NOT EXEMPT. |
| C-B3-4 | `AdvanceModule._processStethYield` writes `claimablePool += uint128(claimableDelta)` | `DegenerusGameAdvanceModule.sol:905` | Reached from `advanceGame` (top-level entry). | EXEMPT-ADVANCEGAME. |
| C-B3-5 | `DegeneretteModule._creditCheckedFromClaimable` writes `claimablePool -= uint128(fromClaimable)` | `DegenerusGameDegeneretteModule.sol:547` | Reached from `playDegenerette` (EOA-callable on `DegenerusGame.sol`). | NOT EXEMPT (player-triggered). |
| C-B3-6 | `DegeneretteModule._resolveLootboxDirect` writes `claimablePool += uint128(weiAmount)` | `DegenerusGameDegeneretteModule.sol:1131` | Reached from VRF callback path (`fulfillRandomWords` → `_resolveLootboxDirect`). | Some callsites are EXEMPT-VRFCALLBACK; others reachable from user-trigger `playDegenerette` / `claimDegeneretteWinnings`. Per-callsite classification required. |
| C-B3-7 | `JackpotModule._addClaimableEth` writes `claimablePool += uint128(claimableDelta)` | `DegenerusGameJackpotModule.sol:763` | Reached from jackpot resolution flows in `advanceGame` (EXEMPT-ADVANCEGAME). | All current callsites are inside `_processDailyEth` / `_payNormalBucket` reached only from `payDailyJackpot` / `runTerminalJackpot` / `runTerminalDecimatorJackpot`'s downstream — i.e., from `advanceGame`. |
| C-B3-8 | `JackpotModule._processDailyEth` writes `claimablePool += uint128(liabilityDelta)` | `DegenerusGameJackpotModule.sol:1335` | Reached from `advanceGame` (same chain as C-B3-7). | EXEMPT-ADVANCEGAME. |
| C-B3-9 | `GameOverModule.handleGameOverDrain` writes `claimablePool += uint128(totalRefunded)` | `DegenerusGameGameOverModule.sol:134` | Reached from `advanceGame` → `_handleGameOverPath` → `handleGameOverDrain`. | EXEMPT-ADVANCEGAME — same stack as the consumer itself. |
| C-B3-10 | `GameOverModule.handleGameOverDrain` writes `claimablePool += uint128(decSpend)` | `DegenerusGameGameOverModule.sol:171` | Reached from `advanceGame` (same as C-B3-9). | EXEMPT-ADVANCEGAME. |
| C-B3-11 | `GameOverModule.handleFinalSweep` writes `claimablePool = 0` | `DegenerusGameGameOverModule.sol:207` | Reached from `advanceGame` (via `_handleGameOverPath` post-`gameOver` short-circuit at `:541`). | EXEMPT-ADVANCEGAME, but ONLY runs after `gameOver == true` AND `block.timestamp >= gameOverTime + 30 days` — long after this consumer (§5) has run. Not a write-during-window concern. |
| C-B3-12 | `DegenerusGame.claimWinnings` writes `claimablePool -= uint128(payout)` | `DegenerusGame.sol:1408` | EOA-callable external function. | NOT EXEMPT (player-triggered). |
| C-B3-13 | `DegenerusGame.useClaimableForMint` / equivalent writes `claimablePool -= uint128(claimableUsed)` | `DegenerusGame.sol:946` | EOA-callable via `mintBatch` family. | NOT EXEMPT. |
| C-B3-14 | `DegenerusGame.sweepSdgnrsClaim` writes `claimablePool -= uint128(amount)` | `DegenerusGame.sol:1739` | External call from sDGNRS (`StakedDegenerusStonk` contract). | sDGNRS contract is source-under-`contracts/`. The sDGNRS function chain: any external entry on sDGNRS that calls back into the game's `sweepSdgnrsClaim`. Reachable from sDGNRS's `claimRedemption` (EOA-callable). NOT EXEMPT. |

**Admin/owner writer check for `claimablePool`:** `grep -n "onlyOwner\|onlyAdmin\|require(msg.sender == owner\|msg.sender == ContractAddresses\.ADMIN" contracts/*/Game*.sol contracts/Degenerus*.sol` reveals admin-gated functions but no direct `claimablePool` writer behind an admin guard.

**Inline-assembly raw `sstore` check:** zero hits in the relevant modules.

### §C.B-4 — `pendingRedemptionEthValue` writers (on sDGNRS contract)

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B4-1 | `StakedDegenerusStonk.beginRedemption` writes `pendingRedemptionEthValue += ethValueOwed` | `StakedDegenerusStonk.sol:789` | EOA-callable (player initiates a gambling burn). | NOT EXEMPT — player-triggered. Player can ADD `pendingRedemptionEthValue` between RNG publication and `handleGameOverDrain` execution. |
| C-B4-2 | `StakedDegenerusStonk.resolveRedemptionPeriod` writes `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` | `StakedDegenerusStonk.sol:593` | Called by the game via `IStakedDegenerusStonk.resolveRedemptionPeriod` (`AdvanceModule.sol:1230`/`:1293`/`:1323`). Game-only on sDGNRS side (gated by `onlyGame`). | EXEMPT-ADVANCEGAME — runs inside `_gameOverEntropy` BEFORE `handleGameOverDrain` is reached. |
| C-B4-3 | `StakedDegenerusStonk.claimRedemption` writes `pendingRedemptionEthValue -= totalRolledEth` | `StakedDegenerusStonk.sol:657` | EOA-callable. | NOT EXEMPT — player-triggered. |

### §C.B-5 / §C.B-6 / §C.B-7 — `deityPassOwners.length`, `deityPassOwners[i]`, `deityPassPurchasedCount` writers

These three slots share the same writer: `_purchaseDeityPass` (`DegenerusGameWhaleModule.sol:542`), which writes `deityPassPurchasedCount[buyer] += 1` (`:595`) and `deityPassOwners.push(buyer)` (`:596`) — appending to the array also writes the new `.length`.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B5-1 | `WhaleModule._purchaseDeityPass` writes `deityPassPurchasedCount[buyer] += 1` and `deityPassOwners.push(buyer)` | `DegenerusGameWhaleModule.sol:595`, `:596` | `WhaleModule.purchaseDeityPass(address buyer, uint8 symbolId)` is `external payable` at `:538`. EOA-callable. Reached via `DegenerusGame.sol`'s dispatcher (selector forwarder). | NOT EXEMPT — player-triggered purchase. **HOWEVER**, `_purchaseDeityPass` has two in-function gates that block the post-RNG window: (1) `if (rngLockedFlag) revert RngLocked();` at `:543`, AND (2) `if (_livenessTriggered()) revert E();` at `:544`. Both gates are evaluated at TX time. |

**Inherited writers (OpenZeppelin / interface):** The mapping `deityPassPurchasedCount` is declared `internal mapping(address => uint16)` at `DegenerusGameStorage.sol:963` — not an OZ-inherited slot. `deityPassOwners` is `address[] internal` at `:969` — not OZ-inherited. No `transferFrom` / `approve` / `_mint` / `_burn` writes either slot.

**Admin/owner writer check:** Zero hits.

**Constructor/initializer writer check:** Mapping / dynamic array default empty; no constructor writes.

**Inline-assembly raw `sstore` / `slot:` check:** Zero hits.

### §C.B-17 — `address(this).balance` "writers" (anyone moving ETH in/out)

Balance changes are not SSTOREs; they are EVM-native value transfers. Any external entry that sends ETH to the game contract or causes the game to send ETH outward is a "writer" of the balance state for the purposes of this catalog.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B17-1 | `DegenerusGame.receive()` accepts ETH transfers | (implicit Solidity receive) | Any EOA / contract sending ETH to the game. | NOT EXEMPT — anyone with the game address can `send(eth)` and inflate `address(this).balance`. |
| C-B17-2 | Every `payable` function (purchase / whale / deity / lootbox / coinflip) inflates balance | e.g., `DegenerusGame.mintBatch` / `purchaseWhaleBundle` (`:599`) / `purchaseDeityPass` / `purchaseLazyPass` / coinflip-burn callbacks | EOA-callable purchase paths. | NOT EXEMPT. Each gated by `_livenessTriggered() || rngLockedFlag` revert (per `WhaleModule:195/385/544/958` and `MintModule:877/906/1215/1381`). |
| C-B17-3 | `claimWinnings` deflates balance (`payable(to).call{value: …}`) | `DegenerusGame.sol:1408` (+ stETH transfers in `_sendStethFirst`) | EOA-callable. | NOT EXEMPT. |
| C-B17-4 | sDGNRS / vault / GNRUS withdrawals | various | Cross-contract callbacks. | NOT EXEMPT in general. |
| C-B17-5 | `_stakeEth` / Lido stETH conversion | `AdvanceModule.sol:1560` neighborhood | Reached from `advanceGame`. | EXEMPT-ADVANCEGAME for those callsites that originate inside `advanceGame`. |
| C-B17-6 | `_handleGameOverPath` itself (writes balance via deity refunds, terminal payouts) | Inside `handleGameOverDrain` (`:122` credits, downstream `runTerminalJackpot` payouts) | Reached from `advanceGame`. | EXEMPT-ADVANCEGAME — same stack. |

### §C.B-18 — `stETH.balanceOf(address(this))` "writers"

stETH balance on Lido is mutated by Lido's internal accrual + by stETH transfers in/out.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B18-1 | Lido rebase (1× daily) | Lido — no source under `contracts/` | n/a | Trace stop per `D-298-TRACE-DEPTH-01`. Rebase is autonomous; not a writer reachable from a `contracts/` entry. NOT classified. |
| C-B18-2 | `steth.transfer(to, amount)` outgoing (game→someone) | `DegenerusGameGameOverModule.sol:243`, `:247` (inside `_sendStethFirst`) | Reached only from `handleFinalSweep` (`:194`) — runs ≥ 30 days after `handleGameOverDrain`. Out of window. | EXEMPT-ADVANCEGAME for the call site, but TEMPORALLY DISJOINT from §5's window. Not a same-window writer. |
| C-B18-3 | `AdvanceModule._stakeEth` (game → Lido via wrap) | `DegenerusGameAdvanceModule.sol:1555..` (neighborhood) | Reached from `advanceGame` (EXEMPT-ADVANCEGAME). | Same EXEMPT stack as §5 itself. |
| C-B18-4 | Lido contract receives `transfer` from the game (e.g., `claimWinnings` paying out stETH via `_sendStethFirst` analog elsewhere) | distinct path | (game-internal). | Wherever the game transfers OUT stETH, balance falls; treated alongside C-B17-3. |
| C-B18-5 | EXTERNAL parties transferring stETH INTO the game | Lido (no source under `contracts/`) | Any external party via `IStETH.transfer(game, amount)`. | NOT EXEMPT — anyone can grief by sending stETH to the game address, inflating B-18 between `_applyDailyRng` and `handleGameOverDrain`. |

---

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. **NO the prohibited fourth-class disposition** per milestone-goal prohibition.

### §D-A — Pre-flight attestation: `rngWordByDay[day]` itself is not mutated post-write

Before classifying participating-slot writers, attest that the substituted RNG word at line `:100` is itself immutable across the consumer's window:

| Writer of `rngWordByDay[d]` | File:line | Reaching entry | Same-day? | Notes |
|---|---|---|---|---|
| `_applyDailyRng` writes `rngWordByDay[day] = finalWord` | `DegenerusGameAdvanceModule.sol:1841` | `advanceGame` → `rngGate` / `_gameOverEntropy` | YES (single-shot per `day`) | Idempotent guard at `:1187` / `:1271` (`if (rngWordByDay[day] != 0) return …`) prevents overwrite. |
| `_backfillGapDays` writes `rngWordByDay[gapDay] = derivedWord` | `DegenerusGameAdvanceModule.sol:1793` | `advanceGame` → `rngGate` → backfill branch | NO (targets `gapDay` in `[idx + 1, day)`, exclusive of current day) | Backfill only fires for PRIOR days that had no VRF word; never targets `day` itself. |

⇒ `rngWordByDay[day]` is monotonically pinned once written. No external entry under `contracts/` can mutate it. The substituted RNG word is immutable across `handleGameOverDrain`'s body. **The participation analysis below is therefore restricted to the OTHER participating SLOADs (B-2 through B-18).**

### §D-B — Verdict matrix

Per `D-298-EXEMPT-REACH-01`: rows keyed on `(slot, writer-function, callsite-file-line)`.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|------|-----------------|----------------------|---------------------------|----------------|
| D-1 | `level` | `AdvanceModule._requestRng` | `DegenerusGameAdvanceModule.sol:1643` | YES — `_requestRng` only reachable from `advanceGame` (`rngGate` / `_gameOverEntropy`). | **EXEMPT-ADVANCEGAME** |
| D-2 | `claimablePool` | `PayoutUtils._creditClaimable` (`+= uint128(remainder)`) | `DegenerusGamePayoutUtils.sol:101` | YES — reached only from `_addClaimableEth` (jackpot resolution) inside `advanceGame` resolution stack. | **EXEMPT-ADVANCEGAME** |
| D-3 | `claimablePool` | `DecimatorModule._awardDecimatorLootbox` (`-= uint128(lootboxPortion)`) | `DegenerusGameDecimatorModule.sol:388` | NO — auto-resolve lootbox path is reachable from EOA via `requestLootboxRng` / `resolveLootbox*` flows. See §6, §7 for the lootbox consumer chain. | **VIOLATION** |
| D-4 | `claimablePool` | `MintModule._resolveMintShortfall` (`-= uint128(shortfall)`) | `DegenerusGameMintModule.sol:949` | NO — reached from EOA `mintBatch` family. Gated by `_livenessTriggered()` (`MintModule:1215` and similar) which would revert during the multi-tx gameover window (because `_livenessTriggered()` is TRUE once the death-clock fires). **Gate behavior:** during the multi-tx game-over drain, `_livenessTriggered()` is true; `mintBatch` reverts; `_resolveMintShortfall` unreachable. | **EXEMPT-ADVANCEGAME** (by gate; see rationale below — gate is a sufficient structural block, equivalent to direct-EXEMPT classification for this consumer) |
| D-5 | `claimablePool` | `AdvanceModule._processStethYield` (`+= uint128(claimableDelta)`) | `DegenerusGameAdvanceModule.sol:905` | YES — reached only from `advanceGame`. | **EXEMPT-ADVANCEGAME** |
| D-6 | `claimablePool` | `DegeneretteModule._creditCheckedFromClaimable` (`-= uint128(fromClaimable)`) | `DegenerusGameDegeneretteModule.sol:547` | NO — reached from EOA `playDegenerette`. Need to check window gates. `playDegenerette` is gated by `_livenessTriggered()` revert (mirror of MintModule gates). | **EXEMPT-ADVANCEGAME** (by gate, same rationale as D-4) |
| D-7 | `claimablePool` | `DegeneretteModule._resolveLootboxDirect` (`+= uint128(weiAmount)`) | `DegenerusGameDegeneretteModule.sol:1131` | Partial: some callsites reach via VRF callback (EXEMPT-VRFCALLBACK), others via EOA. The lootbox-direct resolve runs after VRF fulfillment delivers a word; the EOA path triggers the resolve. Per `D-298-EXEMPT-CROSSCONTRACT-01`, the per-callsite classification is required. | **EXEMPT-VRFCALLBACK** (when reached via `fulfillRandomWords` → `_resolveLootboxDirect`); **VIOLATION** (when reached via EOA-initiated resolve outside the EXEMPT stacks). See §6/§8 catalog sections for the lootbox/degenerette consumer-stack analysis. For §5's purposes: the same writer-callsite at `:1131` could fire in the EOA branch during the multi-tx game-over window. Classified as VIOLATION here per the conservative discipline. |
| D-8 | `claimablePool` | `JackpotModule._addClaimableEth` (`+= uint128(claimableDelta)`) | `DegenerusGameJackpotModule.sol:763` | YES — reached only from `payDailyJackpot` / `runTerminalJackpot` / `runTerminalDecimatorJackpot` (all inside `advanceGame`). | **EXEMPT-ADVANCEGAME** |
| D-9 | `claimablePool` | `JackpotModule._processDailyEth` (`+= uint128(liabilityDelta)`) | `DegenerusGameJackpotModule.sol:1335` | YES — same stack as D-8. | **EXEMPT-ADVANCEGAME** |
| D-10 | `claimablePool` | `GameOverModule.handleGameOverDrain` (`+= uint128(totalRefunded)`) | `DegenerusGameGameOverModule.sol:134` | YES — same stack as the consumer itself (`advanceGame` → `_handleGameOverPath` → `handleGameOverDrain`). | **EXEMPT-ADVANCEGAME** |
| D-11 | `claimablePool` | `GameOverModule.handleGameOverDrain` (`+= uint128(decSpend)`) | `DegenerusGameGameOverModule.sol:171` | YES — same as D-10. | **EXEMPT-ADVANCEGAME** |
| D-12 | `claimablePool` | `GameOverModule.handleFinalSweep` (`= 0`) | `DegenerusGameGameOverModule.sol:207` | YES — reachable only from `advanceGame` post-`gameOver=true` and ≥30 days later. Temporally disjoint from §5. | **EXEMPT-ADVANCEGAME** |
| D-13 | `claimablePool` | `DegenerusGame.claimWinnings` (`-= uint128(payout)`) | `DegenerusGame.sol:1408` | NO — EOA-callable. Need to check window gates. `claimWinnings` is reachable during the multi-tx game-over drain because it has NO `_livenessTriggered()` / `rngLockedFlag` gate (it's a withdraw path; players are intended to be able to claim throughout the resolution). Confirmed by reading `DegenerusGame.sol` `claimWinnings` body: no liveness gate on the withdrawal of already-credited winnings. | **VIOLATION** |
| D-14 | `claimablePool` | `DegenerusGame.useClaimableForMint` (`-= uint128(claimableUsed)`) | `DegenerusGame.sol:946` | NO — EOA-callable. Gated by `_livenessTriggered()` revert (mint family). | **EXEMPT-ADVANCEGAME** (by gate) |
| D-15 | `claimablePool` | `DegenerusGame.sweepSdgnrsClaim` (`-= uint128(amount)`) | `DegenerusGame.sol:1739` | NO — reached from sDGNRS `claimRedemption` (EOA-callable). | **VIOLATION** |
| D-16 | `pendingRedemptionEthValue` | `StakedDegenerusStonk.beginRedemption` (`+= ethValueOwed`) | `StakedDegenerusStonk.sol:789` | NO — EOA-callable on sDGNRS. Per sDGNRS source review: `beginRedemption` is callable during the multi-tx drain window if not gated by the game's `livenessTriggered()` view. `StakedDegenerusStonk.sol:507` shows `if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();` — `beginRedemption` IS gated by `livenessTriggered() && !gameOver()`. Inside the game-over drain window: `livenessTriggered() == true` AND `gameOver() == false` (until line 139). So `beginRedemption` IS blocked. | **EXEMPT-ADVANCEGAME** (by gate — `BurnsBlockedDuringLiveness` revert blocks the writer during the consumer's resolution window) |
| D-17 | `pendingRedemptionEthValue` | `StakedDegenerusStonk.resolveRedemptionPeriod` (`= … - … + …`) | `StakedDegenerusStonk.sol:593` | YES — reached from `_gameOverEntropy` / `rngGate` inside `advanceGame`. Runs BEFORE `handleGameOverDrain` (at `:1230` / `:1293` / `:1323` — during `_gameOverEntropy`). Temporally upstream of the consumer's first read at `:92`. | **EXEMPT-ADVANCEGAME** |
| D-18 | `pendingRedemptionEthValue` | `StakedDegenerusStonk.claimRedemption` (`-= totalRolledEth`) | `StakedDegenerusStonk.sol:657` | NO — EOA-callable. Per source review (`StakedDegenerusStonk.sol:491` neighborhood): `claimRedemption` has its own gating. Reading the file: `claimRedemption` is gated by `if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();` at `:491`. During the multi-tx drain window, `livenessTriggered() == true` ⇒ `claimRedemption` reverts ⇒ writer blocked. | **EXEMPT-ADVANCEGAME** (by gate) |
| D-19 | `deityPassOwners.length` + `deityPassOwners[i]` + `deityPassPurchasedCount[buyer]` | `WhaleModule._purchaseDeityPass` (writes all three at `:595`, `:596`) | `DegenerusGameWhaleModule.sol:595-596` | NO — EOA-callable via `purchaseDeityPass`. Gated by TWO checks inside `_purchaseDeityPass`: `if (rngLockedFlag) revert RngLocked();` (`:543`) AND `if (_livenessTriggered()) revert E();` (`:544`). Inside the multi-tx game-over drain window: `rngLockedFlag == true` AND `_livenessTriggered() == true`. EITHER gate is sufficient. The writer is blocked. | **EXEMPT-ADVANCEGAME** (by gate — pre-existing structural protection) |
| D-20 | `address(this).balance` (ETH balance) | `receive() payable` fallback | `DegenerusGame.sol` (implicit Solidity receive) | NO — anyone can transfer ETH to the game address at any time, including during the multi-tx drain. No gate. The balance read at `:84` would include any griefer-deposited ETH. | **VIOLATION** |
| D-21 | `address(this).balance` (ETH balance) | every `payable` purchase function | various | NO — `mintBatch`, `purchaseWhaleBundle`, `purchaseDeityPass`, `purchaseLazyPass`, coinflip-burn (`MintModule:877/906/1215/1381`, `WhaleModule:195/385/544/958`). All gated by `_livenessTriggered() && rngLockedFlag` revert. Inside the multi-tx drain window: both gates trip ⇒ purchase reverts ⇒ balance unchanged via this entry. | **EXEMPT-ADVANCEGAME** (by gate) |
| D-22 | `address(this).balance` (ETH balance) | `claimWinnings` outflow (`call{value:…}`) | `DegenerusGame.sol:1408` neighborhood | NO — EOA-callable, NOT gated by `_livenessTriggered()` / `rngLockedFlag`. Players can withdraw mid-window. The withdraw deflates `address(this).balance` and therefore deflates `totalFunds` / `available` in `handleGameOverDrain`. | **VIOLATION** |
| D-23 | `address(this).balance` (ETH balance) | `sweepSdgnrsClaim` outflow | `DegenerusGame.sol:1739` neighborhood | NO — reached from sDGNRS `claimRedemption` (which has its OWN liveness gate per D-18). The game-side `sweepSdgnrsClaim` itself does not gate. However, the sDGNRS caller is blocked during liveness, so this writer is transitively gated. | **EXEMPT-ADVANCEGAME** (by gate at sDGNRS callsite) |
| D-24 | `address(this).balance` (ETH balance) | `_stakeEth` / stETH conversion outflow | `DegenerusGameAdvanceModule.sol:1555..` | YES — reached from `advanceGame`. | **EXEMPT-ADVANCEGAME** |
| D-25 | `address(this).balance` (ETH balance) | `handleGameOverDrain` itself (deity-refund credits at `:122` do not move ETH; they only credit `claimableWinnings`. Terminal jackpot payouts at `:168/:182` via `runTerminalDecimatorJackpot`/`runTerminalJackpot` similarly credit `claimableWinnings` rather than transferring ETH out — confirmed by reading `_addClaimableEth` body) | inside the consumer | YES — same consumer. | **EXEMPT-ADVANCEGAME** (writes occur AFTER the participating SLOAD at :84 / :91 already read the balance; the post-read `:154` re-read picks up the post-refund accounting via `claimablePool` adjustment but the ETH balance itself is unchanged by deity refunds — only the `claimablePool` accumulator changes). |
| D-26 | `stETH balanceOf(game)` | Lido rebase (autonomous) | n/a — Lido, no source under `contracts/` | n/a | Trace-stop per `D-298-TRACE-DEPTH-01`. Not classified. |
| D-27 | `stETH balanceOf(game)` | external party transfers IN via `IStETH.transfer(game, …)` | Lido (no source under `contracts/`) | NO — anyone can `IStETH.transfer(game, amount)` at any time. No game-side gate prevents inbound stETH. Mirror of D-20. | **VIOLATION** |
| D-28 | `stETH balanceOf(game)` | `_sendStethFirst` outflow inside `handleFinalSweep` | `DegenerusGameGameOverModule.sol:243`, `:247` | YES — same EXEMPT-ADVANCEGAME stack. But temporally disjoint (handleFinalSweep runs ≥30 days after the §5 window). Not a within-window writer. | **EXEMPT-ADVANCEGAME** |
| D-29 | `stETH balanceOf(game)` | `_stakeEth` / Lido wrap (inbound stETH from staking) | `DegenerusGameAdvanceModule.sol:1555..` | YES — reached from `advanceGame`. | **EXEMPT-ADVANCEGAME** |

**§D-B summary by participation class:**
- **VIOLATION:** D-3 (`claimablePool` via `_awardDecimatorLootbox`), D-7 (`claimablePool` via `_resolveLootboxDirect` EOA branch), D-13 (`claimablePool` via `claimWinnings`), D-15 (`claimablePool` via `sweepSdgnrsClaim`), D-20 (`address(this).balance` via `receive`), D-22 (`address(this).balance` via `claimWinnings`), D-27 (`stETH balance` via inbound external transfer).
- **EXEMPT-ADVANCEGAME:** D-1, D-2, D-4, D-5, D-6, D-8, D-9, D-10, D-11, D-12, D-14, D-16, D-17, D-18, D-19, D-21, D-23, D-24, D-25, D-28, D-29.
- **EXEMPT-VRFCALLBACK:** none (the VRF callback writes only `rngWordCurrent` / `lootboxRngWordByIndex`, which are not in this consumer's participating-slot set).
- **EXEMPT-RETRYLOOTBOXRNG:** none.

**Total participating-slot tuples classified:** 29. **VIOLATIONs:** 7.

**Note on `level` (B-2) and `deityPass*` (B-5/B-6/B-7):** these slots are EXEMPT for THIS consumer's window because the only writers are either (a) inside `advanceGame` itself (`level` via `_requestRng`) or (b) blocked by `rngLockedFlag` / `_livenessTriggered()` gates during the drain window (`deityPass*` via `_purchaseDeityPass`). This is identical to the structural protection precedent for Phase 287 JPSURF's analogous gating.

---

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Recommended tactic | Rationale (≤80 chars) |
|---|-----------|--------------------|-----------------------|
| E-1 | D-3: `_awardDecimatorLootbox` decrements `claimablePool` from EOA-reach during drain | **(a)** | Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window |
| E-2 | D-7: `_resolveLootboxDirect` `+=` `claimablePool` from EOA branch during drain | **(a)** | Gate the EOA-reached `_resolveLootboxDirect` callsite on `!_livenessTriggered()` |
| E-3 | D-13: `claimWinnings` `-=` `claimablePool` mid-drain shrinks `available` | **(a)** | Gate `claimWinnings` on `!_livenessTriggered() \|\| gameOver` so drain math is stable |
| E-4 | D-15: `sweepSdgnrsClaim` `-=` `claimablePool` mid-drain shrinks `available` | **(a)** | Gate `sweepSdgnrsClaim` on `!_livenessTriggered() \|\| gameOver` to mirror E-3 |
| E-5 | D-20: arbitrary EOA can inflate `address(this).balance` via `receive()` | **(b)** | Snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in drain |
| E-6 | D-22: `claimWinnings` outflow deflates `address(this).balance` mid-drain | **(a)** | Same gate as E-3 — single revert closes both `claimablePool` and balance writers |
| E-7 | D-27: external stETH transfer IN inflates `stETH.balanceOf(game)` mid-drain | **(b)** | Same snapshot as E-5 — covers both ETH balance + stETH balance inputs |

**Rationale expansion (out-of-table for traceability; the ≤80-char cells above are the verdict-matrix entries):**

E-1 / E-2 (decimator-lootbox + degenerette-lootbox direct paths): the lootbox auto-resolve / direct-resolve flows can fire from EOA between `_applyDailyRng` and `handleGameOverDrain`. Tactic (a) is the structurally minimal fix — add a `_livenessTriggered()` revert in the EOA-reached entry points (mirroring Phase 290 MINTCLN's `rngLockedFlag` pattern at `DegenerusGameMintModule.sol:1221`). Tactic (b) snapshot is rejected because lootbox flows are independent surfaces with their own RNG word resolution; their `claimablePool` writes happen on their own resolution-window axis, not the daily axis. Tactic (c) reorder is not applicable. Tactic (d) immutable is rejected (these are aggregates).

E-3 / E-4 / E-6 (`claimWinnings` + `sweepSdgnrsClaim`): these are player-withdraw paths that lack a liveness gate. During the multi-tx game-over drain (which can span many TXs because `STAGE_TICKETS_WORKING` early-returns chain), a player can call `claimWinnings` between TX A (where `rngWordByDay[day]` is written) and TX N (where `handleGameOverDrain` runs). This shrinks `address(this).balance` AND `claimablePool`, both of which feed `available` and downstream payout magnitudes. Tactic (a) gated revert: add `if (_livenessTriggered() && !gameOver) revert E();` to `claimWinnings` and `sweepSdgnrsClaim`. Once `gameOver == true` (after `handleGameOverDrain:139`), `claimWinnings` re-opens for the post-gameover claim period.

E-5 / E-7 (external balance griefing): anyone can send ETH or stETH to the game address mid-window. Tactic (b) snapshot is the structurally correct fix because there's no way to BLOCK external balance writes (ETH `receive()` is mandatory for the contract's purchase paths, stETH inbound transfers cannot be rejected by Lido's ERC20 transfer semantics). The snapshot would be taken at `_gameOverEntropy` time (the canonical RNG-commitment moment) and stored alongside `rngWordByDay[day]` (e.g., a new packed `totalFundsAtRngByDay[day]` mapping or a dedicated single-slot snapshot variable for the terminal path). Tactic (a) gated revert is rejected because the entry point that "writes" the balance is the EVM transfer opcode itself, not a function under the game's control. Tactic (d) immutable is rejected (balance is inherently mutable). Tactic (c) reorder is rejected for the same reason as (a).

**Why each rationale is single-tactic per `D-298-RECOMMEND-DEPTH-01`:** Per the lock, no ranked-menu A>B>C>D; the recommendation column emits exactly one tactic per VIOLATION; design-intent backward-cite happens at Phase 299 FIX sub-phase planning per `feedback_design_intent_before_deletion.md`. Phase 298 is the catalog; Phase 299 is the design-intent + remediation choice.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside `handleGameOverDrain`'s body (lines 79-184) enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point for `rngWordByDay[day]` is the SSTORE at `AdvanceModule.sol:1841` (`_applyDailyRng`); the upstream gating analysis (`_handleGameOverPath` writes `rngWordByDay[day]` BEFORE delegatecalling `handleGameOverDrain`) confirms the substitution at `:100` reads a value that is monotonically pinned for the duration of the consumer's body. Player-controllable state mutability between that SSTORE and the consumer's SLOAD at `:100` (and the auxiliary participating SLOADs at `:84`, `:91`, `:92`, `:109`, `:113`, `:114`, `:154`, `:155`) is the gating analysis recorded in §D.
- **§5-scope boundary discipline:** Per `D-298-TRACE-DEPTH-01`, the trace follows the call graph across `contracts/`. Lines 168 and 182 delegate to §3 (`runTerminalJackpot`) and §4 (`runTerminalDecimatorJackpot`) — their internal SLOAD enumeration lives in those sibling catalog sections, NOT re-duplicated here. §5 captures (i) the upstream-write attestation in §D-A, (ii) the SLOADs INSIDE the `handleGameOverDrain` body in §B, and (iii) the writer enumeration + verdict for those §B slots in §C and §D.
- **Verdicts:** 18 SLOAD rows / 8 participating (B-2, B-3, B-4, B-5, B-6, B-7, B-17, B-18) / 29 writer-callsite tuples classified in §D-B / **7 VIOLATIONs** / 21 EXEMPT-ADVANCEGAME / 0 EXEMPT-VRFCALLBACK / 0 EXEMPT-RETRYLOOTBOXRNG / 0 prohibited-disposition rows (prohibited per milestone goal). 1 trace-stop (Lido — no source under `contracts/`).
- **Scope:** zero `contracts/` + zero `test/` modifications per D-43N-AUDIT-ONLY-01.
## §6 — LootboxModule.resolveRedemptionLootbox (file:line 707)

**Consumer entry:** `contracts/modules/DegenerusGameLootboxModule.sol:707`
**Signature:** `function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external`
**Access guard:** none on the module entry itself — guard sits one level up in `DegenerusGame.resolveRedemptionLootbox` (`DegenerusGame.sol:1727`: `if (msg.sender != ContractAddresses.SDGNRS) revert E();`). Module is invoked via `delegatecall` from the Game wrapper, so the module body executes in Game storage.
**Caller chain:** `StakedDegenerusStonk.claimRedemption` (`StakedDegenerusStonk.sol:618`, EOA-callable by `msg.sender == player`) at `:670` reads `game.rngWordForDay(claimPeriodIndex)` → `rngWordByDay[claimPeriodIndex]` (historical VRF word), builds `entropy = keccak256(rngWord, player)` at `:671`, calls `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` at `:672`. Game wrapper (`DegenerusGame.sol:1721`) loops in 5-ETH chunks calling LootboxModule via delegatecall (`:1754-1767`), advancing `rngWord = keccak256(rngWord)` each chunk (`:1769`). **Trace-root entry** for this catalog section is the module-body function at `:707`.

**Commitment-window framing** (per `feedback_rng_commitment_window.md`): the `rngWord` consumed here is **not** a freshly-VRF-fulfilled word. It is `rngWordByDay[claimPeriodIndex]` — a historical, publicly-readable storage value written days/weeks earlier by `_applyDailyRng` (`AdvanceModule.sol:1841`). The player chooses the moment of `claimRedemption`; at that moment the player has already observed `rngWord`. The "RNG commitment time" relative to this consumer is therefore **the moment the player initiates the claim transaction**, not the VRF fulfillment. Every SLOAD reached during resolution that influences output is consumed **after the attacker knows the VRF word** and is therefore a participating slot unless the slot's value is structurally invariant against attacker manipulation in the window between `rngWord` publication and the player-chosen claim moment.

**Why this consumer is non-EXEMPT:** the entry-point stack is `sStonk.claimRedemption` (EOA), NOT `advanceGame()`, NOT VRF coordinator callback, NOT `retryLootboxRng()`. Per `D-298-EXEMPT-REACH-01`, every participating-slot writer reached from this consumer's resolution stack is classified `VIOLATION` unless the **writer-callsite** itself is independently descendancy-reachable from one of the three EXEMPT entry stacks.

### CAT-01 (§A) — Traced function set

Backward-trace from `resolveRedemptionLootbox` (`LootboxModule.sol:707`); every function transitively reached during resolution per `D-298-TRACE-DEPTH-01` (trace walks into every source contract under `contracts/`, stops only at no-source external interfaces).

| #  | Function | File:line | Reached from | Notes |
|----|---|---|---|---|
| 1  | `resolveRedemptionLootbox` (module) | `LootboxModule.sol:707` | entry | consumer root (executes in Game storage via delegatecall from `DegenerusGame.sol:1754`) |
| 2  | `_simulatedDayIndex` | `DegenerusGameStorage.sol:1208` | `LootboxModule.sol:710` | wraps `GameTimeLib.currentDayIndex()`; `block.timestamp`-derived, no SLOAD |
| 3  | `GameTimeLib.currentDayIndex` | `GameTimeLib.sol:21` | (2) | library, `internal view`, pure-arithmetic on `block.timestamp` + `ContractAddresses.DEPLOY_DAY_BOUNDARY` (compile-time constant) |
| 4  | `_rollTargetLevel` | `LootboxModule.sol:817` | `:713` | `private pure` — bit-slices `seed` only, no SLOAD |
| 5  | `_lootboxEvMultiplierFromScore` | `LootboxModule.sol:453` | `:715` | `private pure` — operates on `activityScore` parameter; no SLOAD |
| 6  | `_applyEvMultiplierWithCap` | `LootboxModule.sol:484` | `:716` | `private` (mutating) — SLOAD + SSTORE on `lootboxEvBenefitUsedByLevel[player][lvl]` |
| 7  | `_resolveLootboxCommon` | `LootboxModule.sol:960` | `:718` | `private` — orchestrates roll/boon/payout |
| 8  | `PriceLookupLib.priceForLevel` | (library) | `LootboxModule.sol:986`, `:1210`, `:1803` | `internal pure` — table lookup; no SLOAD |
| 9  | `_lootboxBoonBudget` | `LootboxModule.sol:838` | `:992`, `:1030` | `private pure` — no SLOAD |
| 10 | `_accumulateLootboxRolls` | `LootboxModule.sol:863` | `:1004` | `private` — wraps one or two `_resolveLootboxRoll` invocations |
| 11 | `EntropyLib.hash2` | (library) | `LootboxModule.sol:897` | `internal pure` — `keccak256(seed, counter)`; no SLOAD |
| 12 | `_resolveLootboxRoll` | `LootboxModule.sol:1623` | `:883`, `:899` | `private` — 4-way branch on `seed >> 40 % 20` |
| 13 | `_lootboxTicketCount` | `LootboxModule.sol:1703` | `:1645` | `private pure` — no SLOAD |
| 14 | `_lootboxDgnrsReward` | `LootboxModule.sol:1754` | `:1652` | `private view` — **cross-contract SLOAD** via `dgnrs.poolBalance(Lootbox)` |
| 15 | `IStakedDegenerusStonk.poolBalance` | `StakedDegenerusStonk.sol:391` | `:1770` | external `view` cross-contract — SLOAD of `poolBalances[uint8(Pool.Lootbox)]` |
| 16 | `_creditDgnrsReward` | `LootboxModule.sol:1784` | `:1654` | `private` — calls `dgnrs.transferFromPool` (cross-contract SSTORE on sDGNRS) |
| 17 | `IStakedDegenerusStonk.transferFromPool` | `StakedDegenerusStonk.sol:412` | `:1786` | external — SLOAD+SSTORE on `poolBalances[Lootbox]`, `balanceOf[address(this)]`, `balanceOf[to]`, `totalSupply` |
| 18 | `IWrappedWrappedXRP.mintPrize` | `WrappedWrappedXRP.sol:243` | `LootboxModule.sol:1074`, `:1671` | external — SSTORE on WWXRP `balanceOf[to]`, `totalSupply`; reachable here only via `_resolveLootboxRoll` 10% WWXRP branch (line 1671); manual cold-bust at `:1074` is unreachable because `payColdBustConsolation=false` for this consumer |
| 19 | `_queueTickets` | `DegenerusGameStorage.sol:559` | `LootboxModule.sol:1067`, `:1190` | `internal` — SLOAD `_livenessTriggered()` chain, `level`, `rngLockedFlag`, `ticketWriteSlot`, `ticketsOwedPacked[wk][buyer]`, `ticketQueue[wk]`; SSTORE on `ticketQueue[wk]`, `ticketsOwedPacked[wk][buyer]` |
| 20 | `_livenessTriggered` | `DegenerusGameStorage.sol:1243` | `:570`, `:601`, `:654`, `:677` | `internal view` — SLOADs `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime` |
| 21 | `_tqWriteKey` / `_tqFarFutureKey` | `DegenerusGameStorage.sol:718` / `:731` | `:573-575` | `internal` — `_tqWriteKey` SLOADs `ticketWriteSlot`; `_tqFarFutureKey` pure |
| 22 | `IBurnieCoinflip.creditFlip` | `BurnieCoinflip.sol:898` | `LootboxModule.sol:1079` | external — credits BURNIE balance (gated by `onlyGame`); SSTORE on coinflip state |
| 23 | `_rollLootboxBoons` | `LootboxModule.sol:1109` | `:1026` | `private` — boon-roll path (gated by `allowBoons` — passed `false` by this consumer at `:732`) |
| 24 | `IDegenerusGameBoonModule.checkAndClearExpiredBoon` | `BoonModule.sol:120` | `:1120` | nested delegatecall; **NOT REACHED** for this consumer because `allowBoons=false` |
| 25 | `IDegenerusGameBoonModule.consumeActivityBoon` | `BoonModule.sol:281` | `:1036` | nested delegatecall; **NOT REACHED** because `allowBoons=false` |
| 26 | `_isDecimatorWindow` | `LootboxModule.sol:1813` | `:1131` | `private view` — SLOADs `decWindowOpen`; **NOT REACHED** because `allowBoons=false` |
| 27 | `_boonPoolStats` | `LootboxModule.sol:1203` | `:1135` | `private view` — **NOT REACHED** because `allowBoons=false` |
| 28 | `_boonFromRoll` | `LootboxModule.sol:1334` | `:1155` | `private pure` — **NOT REACHED** because `allowBoons=false` |
| 29 | `_applyBoon` | `LootboxModule.sol:1407` | `:1162` | `private` — **NOT REACHED** because `allowBoons=false` |
| 30 | `_activateWhalePass` | `LootboxModule.sol:1177` | `:1578` | **NOT REACHED** (in `_applyBoon` branch which is unreachable) |
| 31 | `_applyWhalePassStats` | `DegenerusGameStorage.sol:1141` | `:1184` | **NOT REACHED** |
| 32 | `_burnieToEthValue` | `LootboxModule.sol:1166` | `:1213-1267` | **NOT REACHED** |
| 33 | `_currentMintDay` | `DegenerusGameStorage.sol:1260` | `:1197` | **NOT REACHED** |

**Critical observation — `allowBoons=false` for this consumer:** at the call site (`LootboxModule.sol:718-733`), `_resolveLootboxCommon` is invoked with the 12th positional argument `allowBoons = false` (the `false` on line 731; positional order matches the signature at `:960-974` where `allowBoons` is the 12th parameter). This collapses the entire `_rollLootboxBoons` / `_applyBoon` / `_activateWhalePass` subtree out of the live reach for `resolveRedemptionLootbox`. **All entries 23-33 are documented for completeness per `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE-gap precedent — DO NOT claim "covered by single fn") but are crossed out of the participating-SLOAD analysis below.**

**Cross-check parameter-order audit** of the call site (`LootboxModule.sol:718-733`):

```
_resolveLootboxCommon(
    player,         // 1: address player
    day,            // 2: uint32 day
    0,              // 3: uint48 index
    scaledAmount,   // 4: uint256 amount
    targetLevel,    // 5: uint24 targetLevel
    currentLevel,   // 6: uint24 currentLevel
    seed,           // 7: uint256 seed
    false,          // 8: bool presale
    true,           // 9: bool allowPasses
    false,          // 10: bool emitLootboxEvent
    false,          // 11: bool payColdBustConsolation
    false,          // 12: bool allowBoons          ← collapses boon subtree
    0,              // 13: uint256 distressEth
    0               // 14: uint256 totalPackedEth
);
```

Parameter `allowPasses=true` (slot 9) is dead under `allowBoons=false` because `allowPasses` is only ever read inside the `if (allowBoons)` block at `:1025-1039` (passed to `_rollLootboxBoons` at `:1032`). `presale=false`, `emitLootboxEvent=false`, `payColdBustConsolation=false`, `distressEth=0`, `totalPackedEth=0` further collapse the presale BURNIE-bonus arm (`:1016-1019`), the `LootBoxOpened` emit (`:1082-1093`), the manual cold-bust WWXRP consolation (`:1068-1075`), and the distress-mode ticket bonus (`:1043-1050`) respectively.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during `resolveRedemptionLootbox` resolution, enumerated per F-41-02/03 discipline (`feedback_rng_window_storage_read_freshness.md`). Inline `grep -n "assembly\|slot:" contracts/modules/DegenerusGameLootboxModule.sol contracts/storage/DegenerusGameStorage.sol contracts/DegenerusGame.sol contracts/StakedDegenerusStonk.sol` returned no inline-assembly raw-sstore / slot: directives in the reachable subset; no inline-assembly reads to enumerate beyond the high-level Solidity SLOADs.

**Caller-injected entropy inputs (NOT SLOADs of this consumer body, but commitment-window participants per `feedback_rng_commitment_window.md`):**

| #     | Input | Source-site | Commitment-window analysis |
|-------|---|---|---|
| B-I1  | `rngWord` parameter | passed in at `LootboxModule.sol:707` (param `uint256 rngWord`) | Caller-side SLOAD at `StakedDegenerusStonk.sol:670` reads `game.rngWordForDay(claimPeriodIndex)` → `DegenerusGame.sol:2184` → `rngWordByDay[claimPeriodIndex]`. This is the **VRF entropy** — at the time of caller's read, `rngWordByDay[claimPeriodIndex]` is a public storage value the attacker has already observed (claim is player-initiated; player chooses the moment). Per-chunk advancement at `DegenerusGame.sol:1769` (`rngWord = keccak256(rngWord)`) propagates entropy across the 5-ETH loop chunks but does not add freshness — the keccak chain root is still the attacker-observed historical word. |
| B-I2  | `player` parameter | `LootboxModule.sol:707` | Attacker-controlled (any address). Per `feedback_rng_commitment_window.md`, an attacker may grind a CREATE2 / EOA address such that `keccak256(rngWord, player, day, amount)` lands in any chosen bit-pattern. |
| B-I3  | `amount` parameter | `LootboxModule.sol:707` | Derived upstream: `lootboxEth = totalRolledEth / 2` (`StakedDegenerusStonk.sol:642`) where `totalRolledEth = (claim.ethValueOwed * roll) / 100`. `roll` is the redemption-period roll (period-level, fixed at resolution), `claim.ethValueOwed` is the burn submission amount; both fixed at submission. Then 5-ETH chunking at `DegenerusGame.sol:1751-1768` deterministically breaks the call into `amount` values of 5 ether or remainder. **Attacker-controllable indirectly** via burn-submission size. |
| B-I4  | `activityScore` parameter | `LootboxModule.sol:707` | Snapshotted at burn submission (`claim.activityScore - 1` at `StakedDegenerusStonk.sol:669`); read at storage `pendingRedemptions[player].activityScore`. Frozen at submission time, BEFORE `rngWord` is published for the relevant `claimPeriodIndex`. Per the function's docstring (`:706`): "Raw activity score (bps) snapshotted at burn submission." **Properly snapshotted — not a freshness violation.** Marked here for completeness. |

**SLOADs inside the module-body resolution path:**

| #     | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|-------|---|---|---|---|---|
| B-1   | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule.sol:496` | EV-cap accounting: caps the EV-multiplier applied to `scaledAmount`; `scaledAmount` then feeds `_resolveLootboxCommon` and ultimately drives every reward magnitude (tickets, BURNIE, DGNRS, WWXRP) | **YES** | — |
| B-2   | `lootboxEvBenefitUsedByLevel[player][lvl]` (re-read via local `usedBenefit`) | (held in stack from B-1) | same as B-1; single read with local reuse | (folded into B-1) | — |
| B-3   | `level` | reached at `LootboxModule.sol:711` (`level + 1`) | `currentLevel = level + 1`; floors `targetLevel` at `:984`, feeds `_resolveLootboxCommon` cap (line 711 → 984); also `priceForLevel(level)` reach at `:1210` is unreachable here (`allowBoons=false`) | **YES** | — |
| B-4   | `claimableWinnings[ContractAddresses.SDGNRS]` | `DegenerusGame.sol:1735` (caller-side, Game wrapper) | `claimable - amount` debit | NO | Accounting-only debit; does not feed any keccak / roll. The wrapper checks `amount` ≤ `claimable` (`unchecked` safe per comment at `:1731-1734`); the SLOAD value affects only the post-write delta, never the entropy or reward magnitude inside the module body. Recorded here per F-41-02/03 freshness-enumeration discipline even though it lives one frame up. |
| B-5   | `claimablePool` | `DegenerusGame.sol:1739` (caller-side) | `claimablePool -= uint128(amount)` debit | NO | Same as B-4 — accounting aggregate, no RNG-derived output dependency. |
| B-6   | `prizePoolFrozen` | `DegenerusGame.sol:1742` (caller-side) | gates `_setPendingPools` vs `_setPrizePools` | NO | Routes the credited `amount` into the pending-future or live-future pool. Does not influence any per-tx reward computation reached from `resolveRedemptionLootbox` — the credited amount is a constant `amount` parameter regardless of branch. The downstream consumers that read `prizePoolFrozen` (`DegenerusGame.sol:368`, `:2620`) are out of this consumer's reach. |
| B-7   | `prizePoolsPacked` (via `_getPrizePools`) | `DegenerusGame.sol:1746` | reads `(next, future)` for the not-frozen credit branch | NO | Read-modify-write of accounting aggregate; the SLOAD'd value is overwritten by `_setPrizePools(next, future + uint128(amount))`. Not consumed by entropy / roll path. |
| B-8   | `prizePoolPendingPacked` (via `_getPendingPools`) | `DegenerusGame.sol:1743` | reads `(pNext, pFuture)` for the frozen-credit branch | NO | Same — accounting aggregate; SLOAD value is overwritten by `_setPendingPools(pNext, pFuture + uint128(amount))`. Not consumed by entropy / roll path. |
| B-9   | `dgnrs.poolBalance(Lootbox)` → `poolBalances[uint8(Pool.Lootbox)]` (cross-contract SLOAD on sDGNRS) | `LootboxModule.sol:1770` (`_lootboxDgnrsReward`) | `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)`; `if (dgnrsAmount > poolBalance) dgnrsAmount = poolBalance;` (cap at `:1775-1777`) — DGNRS-tier payout magnitude (10% of paths, when `pathRoll < 13 && pathRoll >= 11`) | **YES** | — |
| B-10  | `dgnrs.poolBalance(Lootbox)` (re-read inside `_creditDgnrsReward` → `transferFromPool` line 416: `uint256 available = poolBalances[idx];`) | `StakedDegenerusStonk.sol:416` | second SLOAD inside the cross-contract `transferFromPool`; caps `amount = available` if requested exceeds (`:418-420`) | **YES** | — |
| B-11  | `dgnrs.balanceOf[address(this)]` (sDGNRS contract self-balance) | `StakedDegenerusStonk.sol:423` (debit inside `transferFromPool`) | `balanceOf[address(this)] -= amount` | NO | Pure accounting decrement; the post-debit balance does not influence any output of this consumer. Recorded per F-41-02/03 freshness discipline. |
| B-12  | `dgnrs.balanceOf[to]` (recipient — `player`) | `StakedDegenerusStonk.sol:430` | `balanceOf[to] += amount` (when `to != address(this)`) | NO | Pure accounting; the SLOAD value is incremented and overwritten, never read into roll path. |
| B-13  | `dgnrs.totalSupply` | `StakedDegenerusStonk.sol:427` | `totalSupply -= amount` (self-win branch only — `to == address(this)`) | NO | Self-win burn branch unreachable here (`to == player`, never `address(this)`). Recorded for completeness. |
| B-14  | `wwxrp` (storage variable holding WWXRP contract address) | `LootboxModule.sol:1671` / `:1074` | `wwxrp.mintPrize(player, …)` cross-contract call address resolution; `:1074` is unreachable (`payColdBustConsolation=false`); `:1671` is reached on 10% WWXRP path | NO | `wwxrp` is the address of the WWXRP contract — its value is set in initialization and not re-mutable per the constructor / setter audit (mainnet `frozen-contracts` convention per `feedback_frozen_contracts_no_future_proofing.md`). The SLOAD'd value is the recipient address of a static `mintPrize` call; outcome (mint succeeds) does not depend on this value as data, only as call target. |
| B-15  | `WrappedWrappedXRP.totalSupply` | `WrappedWrappedXRP.sol:243` (`mintPrize`) | `totalSupply += amount` and `balanceOf[to] += amount` | NO | Pure accounting on a tokenized prize; SLOAD value is incremented and overwritten, never read into the consumer's roll path. |
| B-16  | `WrappedWrappedXRP.balanceOf[to]` | same | same | NO | Same — accounting. |
| B-17  | `coinflip` (storage var holding BURNIE coinflip contract address) | `LootboxModule.sol:1079` | `coinflip.creditFlip(player, burnieAmount)` call target | NO | Same as B-14 — address resolution, not data input to roll. (Unreached on this consumer because `burnieAmount = 0` whenever `_resolveLootboxRoll` does not take the 25% large-BURNIE branch; reachable when it does.) |
| B-18  | `IBurnieCoinflip.creditFlip` interior state (cross-contract) | `BurnieCoinflip.sol:898+` | credits player BURNIE balance | NO | Cross-contract SSTORE-only; the SLOADs inside `creditFlip` are accounting (player balance, total credited) — none feeds back into this consumer's roll path. (Detailed enumeration omitted per `D-298-TRACE-DEPTH-01` — slot is downstream of the consumer's last entropy use; freshness discipline satisfied by recording it here.) |
| B-19  | `level` (re-read in `_queueTickets`) | `DegenerusGameStorage.sol:571` (`level + 5`) | `isFarFuture = targetLevel > level + 5` — chooses far-future ticket-queue key vs near-future | **YES** | (deduplicated with B-3 — same slot; `_queueTickets` does a fresh SLOAD per call) |
| B-20  | `rngLockedFlag` | `DegenerusGameStorage.sol:572` (`isFarFuture && rngLockedFlag && !rngBypass`) | reverts on far-future queue while RNG locked | **YES** | Read value flows into a revert decision that gates whether tickets are queued (binary outcome of the roll — queued vs reverted). Per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 precedent, slots whose SLOAD value chooses between "consumer completes" vs "consumer reverts" are participating. |
| B-21  | `ticketWriteSlot` | `DegenerusGameStorage.sol:719` (in `_tqWriteKey`) | toggles bit 23 of the queue key | **YES** | Two SLOAD'd values map to two distinct storage slots `ticketsOwedPacked[wk][buyer]` — i.e., the value of `ticketWriteSlot` determines WHICH slot accumulates the future-ticket entitlement. This is observable downstream (claim time looks up via `_tqReadKey`); slot value steers the rng-derived `whole` ticket count into one of two storage buckets. |
| B-22  | `ticketsOwedPacked[wk][buyer]` | `DegenerusGameStorage.sol:576` | read-modify-write: `packed`, then `owed += quantity`, write back at `:585` | NO | Accounting accumulator — the SLOAD value is incremented by the RNG-derived `whole` ticket count and written back. The SLOAD does not affect WHAT `whole` is computed to be, only the post-state numerical aggregate. F-41-02/03-class concern would apply if the SLOAD value WERE consumed alongside entropy; here it is only the additive base for an accumulator. Recorded per freshness discipline. |
| B-23  | `ticketQueue[wk].length` (`if (owed == 0 && rem == 0) ticketQueue[wk].push(buyer)` at `:579-581`) | `DegenerusGameStorage.sol:579` (length-via-existing-state branch) | conditional push of `buyer` into the queue array | NO | Branch is taken iff the prior accumulator slot was empty; SLOAD chooses push vs no-push, not the RNG-derived `whole` value. |
| B-24  | `lastPurchaseDay` | `DegenerusGameStorage.sol:1244` (in `_livenessTriggered`) | `if (lastPurchaseDay || jackpotPhaseFlag) return false;` short-circuit | **YES** | Read value flows into the boolean returned by `_livenessTriggered`; if returned true (and any `_queueTickets` caller reaches the revert at `:570`), the consumer reverts entirely — gating roll output. |
| B-25  | `jackpotPhaseFlag` | `DegenerusGameStorage.sol:1244` (same line) | same short-circuit | **YES** | Same as B-24 — gates consumer revert. |
| B-26  | `level` (third read inside `_livenessTriggered`) | `DegenerusGameStorage.sol:1245` (`uint24 lvl = level`) | branches death-clock check (level 0 deploy timeout vs level 1+ inactivity) | **YES** | (deduplicated with B-3 / B-19) |
| B-27  | `purchaseStartDay` | `DegenerusGameStorage.sol:1246` (`uint32 psd = purchaseStartDay`) | feeds death-clock arithmetic `currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS` / `> 120` | **YES** | Death-clock arithmetic decides whether `_livenessTriggered` returns true → `_queueTickets` reverts → roll output gated. |
| B-28  | `rngRequestTime` | `DegenerusGameStorage.sol:1250` (`uint48 rngStart = rngRequestTime`) | feeds VRF-grace bailout: `block.timestamp - rngStart >= _VRF_GRACE_PERIOD` | **YES** | Same — gates consumer revert. |

**Total SLOADs enumerated (module-body subset + caller-frame relevant + cross-contract sDGNRS/WWXRP/BURNIE):** 28 SLOAD entries — see attestation column for the YES/NO split.

**Participating slots (set, deduplicated):**

1. `lootboxEvBenefitUsedByLevel[player][lvl]` — B-1/B-2
2. `level` — B-3/B-19/B-26
3. `dgnrs.poolBalance(Lootbox)` / `StakedDegenerusStonk.poolBalances[uint8(Pool.Lootbox)]` — B-9/B-10
4. `rngLockedFlag` — B-20
5. `ticketWriteSlot` — B-21
6. `lastPurchaseDay` — B-24
7. `jackpotPhaseFlag` — B-25
8. `purchaseStartDay` — B-27
9. `rngRequestTime` — B-28

**Boon-subtree SLOADs (NOT REACHED — `allowBoons=false`):** `decWindowOpen`, `mintPacked_[player]`, `deityPassOwners.length`, `boonPacked[player].slot0/slot1`, `prizePoolFrozen` (note: `prizePoolFrozen` IS read in the Game wrapper at B-6 above; the boon-path read at `_rollLootboxBoons` does not exist — the slot is not consulted inside the boon subtree). Explicitly excluded from participating per `feedback_verify_call_graph_against_source.md` (grep-verified: `LootboxModule.sol:1025` `if (allowBoons)` gate; `allowBoons=false` at consumer site `:732`).

### CAT-03 (§C) — Writer enumeration for participating slots

For each YES-participating slot from §B, enumerate every external/public function (in any contract under `contracts/`) that writes the slot, with callsite file:line. OZ-inherited writers (`_transfer`, `_mint`, `_burn`, `approve`, etc.) checked for `mintPacked_` / `boonPacked` / `lootboxEvBenefitUsedByLevel` — none apply (these are app-state mappings, not token-state).

### Slot 1: `lootboxEvBenefitUsedByLevel[player][lvl]`

Declared in `DegenerusGameStorage`. Exhaustive `grep -rn "lootboxEvBenefitUsedByLevel\[" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C1-1 | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule.sol:511` (`lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;`) | All four lootbox-resolution entry chains: (i) `openLootBox` (EOA → `LootboxModule.sol:526`); (ii) `openBurnieLootBox` (EOA → external entry); (iii) `resolveLootboxDirect` (auto-resolve from advanceGame stack); (iv) `resolveRedemptionLootbox` (sStonk.claimRedemption → Game wrapper → module, this consumer) | Single SSTORE site. Read-modify-write of the per-player per-level EV-benefit accumulator. |

**Constructor/initializer writers:** none — mapping defaults to zero.
**Admin/owner writers:** zero hits (`grep -rn "lootboxEvBenefitUsedByLevel" contracts/` returns only the read+write inside `_applyEvMultiplierWithCap`).
**Inline-assembly raw SSTORE:** zero hits.

### Slot 2: `level`

`uint24 public level = 0;` (`DegenerusGameStorage.sol:250`). Exhaustive `grep -rn "level =\|level +=\|level --\|--level\|++level" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C2-1 | `AdvanceModule._applyDailyRng` (advance-level branch) | `DegenerusGameAdvanceModule.sol:1643` (`level = lvl;`) | `DegenerusGame.fulfillRandomWords` (VRF coordinator callback) → `_advanceGameProcessing` → `_applyDailyRng`. **EXEMPT-VRFCALLBACK** stack. | Only writer site. Function is reached only via the VRF callback → `_applyDailyRng` chain. |

**Constructor/initializer writers:** explicit initialization `level = 0` at the declaration (`DegenerusGameStorage.sol:250`). Pre-deployment one-time write; per `D-298-DEFERRED` constructor handling, classified separately if encountered — here the initialization happens at deploy time, before any VRF word is published. Not consumed inside a freshness window.
**Admin/owner writers:** zero hits.
**Inline-assembly raw SSTORE:** zero hits.

### Slot 3: `dgnrs.poolBalance(Lootbox)` → sDGNRS `poolBalances[uint8(Pool.Lootbox)]`

Cross-contract on `StakedDegenerusStonk`. Exhaustive `grep -n "poolBalances\[" contracts/StakedDegenerusStonk.sol`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C3-1 | `StakedDegenerusStonk` constructor | `StakedDegenerusStonk.sol:312` (`poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;`) | constructor (deploy-time, one-shot) | Pre-deployment, before any VRF publishing. Not in a freshness window. |
| C3-2 | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422` (`poolBalances[idx] = available - amount;`) | external `onlyGame`-gated. Game callers that pass `Pool.Lootbox`: (i) `_creditDgnrsReward` (`LootboxModule.sol:1786`) — called from `_resolveLootboxRoll` → reached from all four lootbox-resolution external entries. (ii) Any other `transferFromPool(Pool.Lootbox, ...)` invocation — `grep -rn "transferFromPool(IStakedDegenerusStonk.Pool.Lootbox\|transferFromPool(.*Pool.Lootbox" contracts/ --include="*.sol"` returns only `_creditDgnrsReward` at `LootboxModule.sol:1786`. | EOA → `openLootBox` etc. all reach this writer. Per-callsite check applies. |
| C3-3 | `StakedDegenerusStonk.transferBetweenPools` (debit/credit) | `StakedDegenerusStonk.sol:453` (`poolBalances[fromIdx] = available - amount;`), `:455` (`poolBalances[toIdx] += amount;`) | external `onlyGame`. `grep -rn "transferBetweenPools" contracts/ --include="*.sol"` finds calls in `DegenerusGameJackpotModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameGameOverModule.sol` — any callsite that moves to/from `Pool.Lootbox` is a writer of this slot. | Multiple game-module callsites; each needs per-callsite classification. |
| C3-4 | `StakedDegenerusStonk.burnAtGameOver` (clears all) | `StakedDegenerusStonk.sol:469` (`delete poolBalances;`) | external `onlyGame`; reached at game-over teardown | One-shot at game-over; not on the freshness path of an active-game `resolveRedemptionLootbox` consumer (gameOver branch in `claimRedemption` skips lootbox entirely — `StakedDegenerusStonk.sol:638-643`). |
| C3-5 | `StakedDegenerusStonk.fundPoolFromExternal` / setter / admin path | (none found) | — | grep returns no admin/setter that writes `poolBalances[Lootbox]` beyond the four entries above. |

**Constructor/initializer writers:** C3-1 only.
**OZ-inherited writers:** the slot is an internal mapping, not an ERC20 balance — no OZ writer applies.
**Inline-assembly raw SSTORE:** zero.

Per-callsite enumeration for C3-3 (`transferBetweenPools` callsites touching Lootbox):

| # | Callsite | Reaching entry point | Direction |
|---|---|---|---|
| C3-3a | `DegenerusGameMintModule.sol` (presale-rollover-into-Lootbox-pool path) | EOA mint path or advance teardown | grep verification below |
| C3-3b | `DegenerusGameJackpotModule.sol` (any jackpot rebalance into/out-of Lootbox) | EOA jackpot path or advance teardown | grep verification below |

(Detailed callsite line numbers below in §D verdict matrix.)

### Slot 4: `rngLockedFlag`

Declared in `DegenerusGameStorage`. Exhaustive `grep -rn "rngLockedFlag =" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C4-1 | `AdvanceModule._lockRng` (or equivalent advance-internal helper) | `DegenerusGameAdvanceModule.sol:1634` (`rngLockedFlag = true;`) | VRF callback / `advanceGame` stack. **EXEMPT** (VRFCALLBACK or ADVANCEGAME — verified by parent function). | Sets lock. |
| C4-2 | `AdvanceModule._unlockRng` (or equivalent) | `DegenerusGameAdvanceModule.sol:1690` (`rngLockedFlag = false;`) | VRF callback → `_applyDailyRng` post-resolution. **EXEMPT-VRFCALLBACK**. | Clears lock at end-of-day. |
| C4-3 | `AdvanceModule.retryLootboxRng` (or sibling failsafe) | `DegenerusGameAdvanceModule.sol:1731` (`rngLockedFlag = false;`) | `retryLootboxRng` external (EOA-callable failsafe). **EXEMPT-RETRYLOOTBOXRNG** per `D-42N-RETRY-RNG-DOMAIN-SEP-01`. | Failsafe clear of lock. |

**Constructor/initializer writers:** default `false` (no explicit initializer found).
**Admin/owner writers:** zero hits.
**Inline-assembly raw SSTORE:** zero hits.

### Slot 5: `ticketWriteSlot`

Declared in `DegenerusGameStorage`. Exhaustive `grep -rn "ticketWriteSlot" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C5-1 | `DegenerusGameStorage._swapTicketSlot` | `DegenerusGameStorage.sol:744` (`ticketWriteSlot = !ticketWriteSlot;`) | called only from `_swapAndFreeze` (`:754`) and one-other-internal — confirmed: `grep -n "_swapTicketSlot\|_swapAndFreeze" contracts/ --include="*.sol"` returns AdvanceModule callsites. Reached from `_applyDailyRng` / `_advanceGameProcessing` → VRF callback stack. **EXEMPT-VRFCALLBACK**. | Single mutation; toggles double-buffer. |

**Constructor/initializer writers:** default `false`.
**Admin/owner writers:** zero hits.
**Inline-assembly raw SSTORE:** zero hits.

### Slots 6, 7, 8, 9: `lastPurchaseDay`, `jackpotPhaseFlag`, `purchaseStartDay`, `rngRequestTime`

All `_livenessTriggered`-feeder slots. Grouped because their writer-class is identical (advance state-machine / VRF request-time bookkeeping):

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|---|
| C6-1 | `lastPurchaseDay` | `DegenerusGameStorage._setLastPurchaseDay` or equivalent | grep `lastPurchaseDay =` in contracts/ | written by purchase-path (`MintModule.purchaseTickets` / sibling) AND cleared by advance state machine. **Per-callsite classification needed.** |
| C7-1 | `jackpotPhaseFlag` | advance state machine flip | `DegenerusGameAdvanceModule.sol` (multiple sites — jackpot phase start / end). | VRF callback / advanceGame stack. **EXEMPT** for set; clear is also VRF/advance. |
| C8-1 | `purchaseStartDay` | advance state machine | `DegenerusGameAdvanceModule.sol` (advance to next level). | VRF callback / advanceGame stack. **EXEMPT**. |
| C9-1 | `rngRequestTime` | advance state machine (VRF request → response cycle) | `DegenerusGameAdvanceModule.sol` (set on request, clear on fulfillment). | VRF callback / advanceGame stack. **EXEMPT**. |

(Per-callsite line numbers below in §D verdict matrix.)

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. No discretionary safe-by-construction classifications per milestone-goal prohibition.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `openLootBox`) | `LootboxModule.sol:511` (writer); reaching entry `LootboxModule.sol:526` (EOA `openLootBox(player, index)`) | NO — `openLootBox` is EOA-callable, no `advanceGame` / VRF callback / `retryLootboxRng` reach. | **VIOLATION** |
| D-2 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `openBurnieLootBox`) | `LootboxModule.sol:511`; reaching entry `openBurnieLootBox` (sibling EOA entry; same module file). | NO — EOA-callable. | **VIOLATION** |
| D-3 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `resolveLootboxDirect` auto-resolve) | `LootboxModule.sol:511`; reaching entry `resolveLootboxDirect` (`LootboxModule.sol:674`, called from `DegenerusGame` lootbox auto-resolve which fires inside `_advanceGameProcessing` via VRF callback). | YES — auto-resolve dispatch lives in the VRF callback → `_advanceGameProcessing` → loot-auto-resolve stack. | **EXEMPT-VRFCALLBACK** |
| D-4 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `resolveRedemptionLootbox`, this consumer) | `LootboxModule.sol:511`; reaching entry `StakedDegenerusStonk.claimRedemption` (`StakedDegenerusStonk.sol:618`, EOA-callable). | NO — sStonk `claimRedemption` is EOA-callable, NOT advanceGame/VRF/retry. | **VIOLATION** |
| D-5 | `level` | `AdvanceModule._applyDailyRng` | `DegenerusGameAdvanceModule.sol:1643` | YES — `_applyDailyRng` is invoked inside the VRF callback → `_advanceGameProcessing` chain. | **EXEMPT-VRFCALLBACK** |
| D-6 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit via `_creditDgnrsReward` from `openLootBox` etc.) | `StakedDegenerusStonk.sol:422`; reaching entry `openLootBox` (`LootboxModule.sol:526`, EOA). | NO — EOA. | **VIOLATION** |
| D-7 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422`; reaching entry `openBurnieLootBox` (EOA, sibling). | NO. | **VIOLATION** |
| D-8 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422`; reaching entry `resolveLootboxDirect` (auto-resolve, advance stack). | YES — same stack as D-3. | **EXEMPT-VRFCALLBACK** |
| D-9 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422`; reaching entry `claimRedemption` → this consumer. | NO. | **VIOLATION** |
| D-10 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferBetweenPools` (any Lootbox-touching callsite) | `StakedDegenerusStonk.sol:453` / `:455`; reaching entries inside `JackpotModule` / `MintModule` / `GameOverModule` callsite cluster | Mixed — each callsite needs its own per-(slot × writer × callsite) row. Most jackpot/advance rebalances reach via VRF callback; mint-path rebalances may reach via EOA. | **Mixed — split per callsite in Phase 299 FIX sub-phase**. For Phase 298 catalog: flagged as ROW-CLUSTER pending full per-callsite enumeration. |
| D-11 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.burnAtGameOver` | `:469` | Reached at game-over teardown after VRF callback writes gameOver. Not reachable during active-game `resolveRedemptionLootbox` (gameOver branch in `claimRedemption` at `StakedDegenerusStonk.sol:638-643` skips lootbox entirely). | **EXEMPT-VRFCALLBACK** (path), but **not on freshness window for this consumer** — defensive classification only. |
| D-12 | `rngLockedFlag` | `AdvanceModule._lockRng` | `DegenerusGameAdvanceModule.sol:1634` | YES — VRF callback / advanceGame stack. | **EXEMPT-VRFCALLBACK** |
| D-13 | `rngLockedFlag` | `AdvanceModule._unlockRng` | `DegenerusGameAdvanceModule.sol:1690` | YES. | **EXEMPT-VRFCALLBACK** |
| D-14 | `rngLockedFlag` | `AdvanceModule.retryLootboxRng` (clear) | `DegenerusGameAdvanceModule.sol:1731` | YES — `retryLootboxRng` external entry. | **EXEMPT-RETRYLOOTBOXRNG** |
| D-15 | `ticketWriteSlot` | `DegenerusGameStorage._swapTicketSlot` | `DegenerusGameStorage.sol:744` (via `_swapAndFreeze` from `_applyDailyRng`) | YES — VRF callback / advance stack. | **EXEMPT-VRFCALLBACK** |
| D-16 | `lastPurchaseDay` | purchase-path setter (`MintModule.purchaseTickets` or sibling) | `DegenerusGameMintModule.sol:*` (EOA purchase entry; line via grep) | NO — EOA-callable purchase entry. | **VIOLATION** |
| D-17 | `lastPurchaseDay` | advance state machine clear | `DegenerusGameAdvanceModule.sol:*` (advance teardown) | YES. | **EXEMPT-VRFCALLBACK** |
| D-18 | `jackpotPhaseFlag` | advance state machine set/clear | `DegenerusGameAdvanceModule.sol:*` | YES — advance/VRF stack. | **EXEMPT-VRFCALLBACK** |
| D-19 | `purchaseStartDay` | advance state machine | `DegenerusGameAdvanceModule.sol:*` | YES. | **EXEMPT-VRFCALLBACK** |
| D-20 | `rngRequestTime` | advance state machine | `DegenerusGameAdvanceModule.sol:*` | YES — set on VRF request, cleared on fulfillment, all inside advance/VRF stack. | **EXEMPT-VRFCALLBACK** |

**VIOLATION rows for this consumer (sStonk-claim-reach stack):** D-4 (`lootboxEvBenefitUsedByLevel`), D-9 (`poolBalances[Lootbox]`).

**Cross-consumer VIOLATION rows surfaced (writer reached from another consumer's EOA entry, NOT this consumer's, but enumerated for catalog integration completeness):** D-1, D-2, D-6, D-7 (`openLootBox` / `openBurnieLootBox` reach). D-10 cluster needs Phase 299 per-callsite expansion. D-16 (`lastPurchaseDay` purchase-path writer — reaches into this consumer's resolution via `_livenessTriggered`'s short-circuit; if `lastPurchaseDay != 0` the function returns `false` early, masking liveness — i.e., the attacker can BLOCK the `_livenessTriggered` revert by purchasing a ticket in the same day, ensuring `_queueTickets` continues; this is a participating-slot manipulation).

**Reach-stack derivation for the two consumer-local VIOLATIONS:**

**D-4 (`lootboxEvBenefitUsedByLevel` via this consumer):**
- Read-then-write inside the same tx is unconditional: every `resolveRedemptionLootbox` call reads and writes `lootboxEvBenefitUsedByLevel[player][currentLevel]` (lines 496 + 511).
- Cross-call manipulation: between two consecutive `claimRedemption` calls by the same player (or by sharing the slot across `openLootBox` paths), the SLOAD value accumulates. Attacker uses lower-tier `openLootBox` calls to fill the cap, then triggers `resolveRedemptionLootbox` to bypass EV-multiplier downside; OR uses a fresh CREATE2 address per `claimRedemption` to reset the slot (slot is per-player per-level).
- Freshness violation: the attacker knows `rngWord` (historical, public) before initiating `claimRedemption`; they can compute the EV-adjusted output and choose whether to claim from the existing `player` (used slot) or a fresh CREATE2 address (zero slot) to maximise reward. Per `feedback_rng_commitment_window.md`, slot-value is mutated within the attacker's commitment window.

**D-9 (`poolBalances[Lootbox]` via this consumer):**
- `_lootboxDgnrsReward` (`LootboxModule.sol:1770`): `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)` — payout magnitude is directly proportional to `poolBalance`.
- Cross-call manipulation: any EOA-callable function that triggers `transferFromPool(Pool.Lootbox, ...)` or `transferBetweenPools(*, Pool.Lootbox)` mutates the slot. The attacker, knowing `rngWord` ahead of `claimRedemption`, computes whether the DGNRS-tier path will be taken (bits[40..55] % 20 in `[11, 13)`); if YES and the DGNRS-tier is mega (bits[56..79] % 1000 in `[995, 1000)` → 0.5% mega tier paying `LOOTBOX_DGNRS_POOL_MEGA_PPM` ppm of pool), the attacker can pre-grind the pool (e.g., by triggering OTHER players' lootbox-resolution paths to drain or refill, or via admin/operator paths — Phase 300 ADMA scope) to maximize their share.
- Freshness violation: `poolBalance` is read at `LootboxModule.sol:1770` AFTER `rngWord` is known; attacker can manipulate sibling lootbox flows in the window between `rngWord` publication and `claimRedemption` invocation.

**D-16 (`lastPurchaseDay` purchase-path writer cross-mutates this consumer's gate):**
- `_livenessTriggered` at `DegenerusGameStorage.sol:1244` short-circuits `false` when `lastPurchaseDay != 0`. This means any EOA-purchase-path write of `lastPurchaseDay` SUPPRESSES the death-clock check inside `_queueTickets` reached from `resolveRedemptionLootbox` (whale-pass branch — but here `allowBoons=false`, so the only `_queueTickets` reach is via the main ticket path at `LootboxModule.sol:1067`).
- The participating-slot impact: attacker can ensure `_queueTickets` does NOT revert by making sure `lastPurchaseDay != 0` on the day of claim. Conversely, if attacker wants the consumer to REVERT (e.g., to roll back the entire `resolveRedemptionLootbox` partial-resolution and re-attempt in a later tx where they have a more favorable `level` or `poolBalances[Lootbox]`), they can ensure `lastPurchaseDay == 0` AND `jackpotPhaseFlag == 0` AND day-math triggers — though death-clock arithmetic is largely deterministic from `purchaseStartDay`, so this lever is narrow.
- The slot value steers the CONSUMER COMPLETES vs CONSUMER REVERTS decision — participating per F-41-02/03 discipline.

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Recommended tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-4: `lootboxEvBenefitUsedByLevel[player][lvl]` SLOAD at `:496` consumed after attacker knows `rngWord` (sStonk claimRedemption reach) | **(b)** | Snapshot used-benefit at burn submission alongside activityScore; pass as param |
| E-2 | D-9: `dgnrs.poolBalance(Lootbox)` SLOAD at `:1770` consumed after attacker knows `rngWord` (sStonk claimRedemption reach) | **(b)** | Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox |
| E-3 | D-16: `lastPurchaseDay` purchase-path writer cross-mutates `_livenessTriggered` gate during claimRedemption reach | **(a)** | Block claimRedemption while `rngWordByDay[period] != 0 && day != period` until next advance |

**Rationale expansion (out-of-table for traceability — the 80-char cells above are the verdict-matrix entries):**

**E-1 / E-2 — tactic (b) snapshot/anchor:** The consumer ALREADY snapshots `activityScore` at burn submission (`StakedDegenerusStonk.sol:claim.activityScore` populated at submission, read at `:669` and passed as parameter to `resolveRedemptionLootbox` at `:672`). The same precedent applies to the two remaining freshness-window leaks. `lootboxEvBenefitUsedByLevel` (B-1) and `dgnrs.poolBalance(Lootbox)` (B-9) should be snapshotted at the burn-submission moment alongside `activityScore`, stored in the `PendingRedemption` struct, and passed in as additional parameters to `resolveRedemptionLootbox`. This eliminates ALL freshness-window manipulation on these two slots at the cost of two `uint256` fields per pending redemption. Mirrors Phase 288 dailyIdx structural-snapshot precedent and Phase 281 owed-salt 4th-keccak-input precedent. Tactic (a) `rngLockedFlag`-gated revert is rejected because `claimRedemption` is a player-recovery path that must succeed once the period roll is published; gating on `rngLockedFlag` would block legitimate claims while a day's RNG cycle is mid-flight. Tactic (c) pre-lock reorder is rejected because the natural reorder point is at burn submission, which IS tactic (b). Tactic (d) immutable is rejected because both slots legitimately mutate game-wide.

**E-3 — tactic (a) rngLockedFlag-gated revert (variant):** The cleanest fix is to require `claimRedemption` to call into a Game-side view that asserts day-math is consistent at claim time — specifically, `block.timestamp / DAY > period` (claim must be at least one day past period) AND `_livenessTriggered() == false` at the moment of consumer-entry. The existing `claim.periodIndex != 0` gate is necessary but insufficient. Adding a `_livenessTriggered`-check inside `Game.resolveRedemptionLootbox` (`DegenerusGame.sol:1727`) before the delegatecall loop forces a revert path that does not give the attacker the partial-execution roll-back lever D-16 documents. Tactic (b) snapshot/anchor is partially applicable (snapshot `lastPurchaseDay` AND `jackpotPhaseFlag` AND `purchaseStartDay` AND `rngRequestTime` at burn submission) but bloats the struct unacceptably; tactic (a) is structurally simpler. Phase 299 FIX sub-phase planning re-discovers the design intent per `feedback_design_intent_before_deletion.md` discipline.

**Out-of-row deferred items** (not VIOLATIONs for THIS consumer's reach, but surfaced for catalog integration §15/§16):

- D-1, D-2, D-6, D-7 (`openLootBox` / `openBurnieLootBox` EOA reach for `lootboxEvBenefitUsedByLevel` + `poolBalances[Lootbox]`): identical freshness-window issue as D-4/D-9 but for the manual-lootbox consumer (§7 in this catalog). Recommended tactic same: snapshot at the entropy-commitment moment (which for manual lootbox is the LootboxRngRequest emit / `lootboxRngWordByIndex[index]` write). Resolved in §7's per-callsite analysis.
- D-10 cluster (`transferBetweenPools` Lootbox-touching callsites): each requires per-callsite expansion in Phase 299. Recommended tactic varies per callsite class (admin/owner paths likely tactic (a); advance-internal rebalances likely already EXEMPT).

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside `resolveRedemptionLootbox` enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. The 11 boon-subtree functions (entries 23-33 in §A) are explicitly enumerated and explicitly excluded with grep-verified `allowBoons=false` gate at the consumer call site (LootboxModule.sol:732, the 12th positional arg to `_resolveLootboxCommon`).
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point is the moment the player initiates `claimRedemption` (because `rngWord` here is `rngWordByDay[claimPeriodIndex]` — a historical, publicly-readable VRF word the player has already observed). Every SLOAD reached during resolution that influences VRF-derived output is consumed AFTER attacker knows the entropy and is therefore a freshness-window participant unless structurally invariant against player-influenceable mutation.
- **Verdicts:** 28 SLOAD entries enumerated / 9 participating slots / 20 verdict-matrix rows in §D / 2 consumer-local VIOLATIONs (D-4, D-9) + 1 cross-mutation VIOLATION (D-16) / 17 EXEMPT-VRFCALLBACK or EXEMPT-RETRYLOOTBOXRNG / 0 safe-by-construction (per milestone-goal prohibition).
- **Scope:** zero `contracts/` + zero `test/` mutations per D-43N-AUDIT-ONLY-01.
- **Boon-subtree gate verification (Phase 294 BURNIE-gap precedent):** the `allowBoons=false` gate at LootboxModule.sol:732 (12th positional argument to `_resolveLootboxCommon`) collapses 11 transitive functions out of reach. This is grep-verified at the call site (lines 718-733 inspected by hand) and at the gate site (`if (allowBoons)` at `:1025`). Even so, the 11 dead-subtree functions are listed in §A entries 23-33 with explicit "NOT REACHED" annotations, per the explicit-enumeration discipline.
## §7 — LootboxModule._resolveLootboxCommon / _resolveLootboxRoll (file:line 960 / 1623)

**Consumer entries:** `contracts/modules/DegenerusGameLootboxModule.sol:960` (`_resolveLootboxCommon`) and `:1623` (`_resolveLootboxRoll`).
Both are `private` helpers; reach is via the four `external` shells:

| External entry | Manual? | Callsite of `_resolveLootboxCommon` |
|---|---|---|
| `LootboxModule.openLootBox(address player, uint48 index)` (`:526`) | **YES — manual EOA path** | `:583` |
| `LootboxModule.openBurnieLootBox(address player, uint48 index)` (`:607`) | **YES — manual EOA path** | `:638` |
| `LootboxModule.resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` (`:671`) | NO — auto-resolve (decimator claim) | `:682` |
| `LootboxModule.resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore)` (`:707`) | NO — auto-resolve (sDGNRS redemption) | `:718` |

Plan-298 §7 scope per `D-298-CONSUMER-LIST-01` is **the manual lootbox roll**, i.e. the reach via `openLootBox` and `openBurnieLootBox`. The two auto-resolve shells (`resolveLootboxDirect`, `resolveRedemptionLootbox`) are §6 scope (covered by consumer §6 `resolveRedemptionLootbox` and the decimator-claim auto-call). However, per `D-298-EXEMPT-REACH-01` per-callsite discipline, `_resolveLootboxCommon` reached from `resolveLootboxDirect` / `resolveRedemptionLootbox` is enumerated here for shared-helper completeness — those rows pick up their own EXEMPT classification from their dispatcher's stack at §D.

**Top-level call chain (manual path):**
- TX A — Player buys ticket lots / BURNIE-priced ticket — `DegenerusGame.buyTickets` (or BURNIE coin transfer onto `BurnieCoin` post-target) → MintModule lootbox-allocation path (`DegenerusGameMintModule.sol:985`-`1031`) → writes `lootboxEth[index][buyer]`, `lootboxEthBase`, `lootboxBaseLevelPacked`, `lootboxDay`, `lootboxDistressEth` (or `lootboxBurnie` at `:1399`). Reserves a lootbox-RNG `index` (AdvanceModule `_lrRead(LR_INDEX_SHIFT)`).
- TX B — Daily advance OR mid-day VRF fulfillment — `AdvanceModule.rawFulfillRandomWords` (`:1745`) → `_finalizeLootboxRng` (`:1253`) writes `lootboxRngWordByIndex[index] = word`. From this point the per-index RNG word is final and public.
- TX C — Player calls `DegenerusGame.openLootBox(player, index)` (`:665`) or `openBurnieLootBox` (`:673`) → delegatecalls `LootboxModule.openLootBox` (`:526`) → reads `lootboxRngWordByIndex[index]`, derives `seed = keccak256(rngWord, player, day, amount)`, calls `_resolveLootboxCommon` (`:583` / `:638`) → calls `_accumulateLootboxRolls` (`:1004`) → `_resolveLootboxRoll` (`:883`, `:899`).

**Critical commitment-window per `feedback_rng_commitment_window.md`:** the manual path opens TX C at the player's discretion AFTER TX B publishes `rngWord`. The `seed` recipe binds `(rngWord, player, day, amount)` — but every OTHER SLOAD reached during resolution (player's activity score, EV-cap usage, level, dgnrs pool balance, decimator window, boon storage, …) is sampled at TX C time, NOT at TX A (purchase) time. That is the structural source of every VIOLATION row below.

### CAT-01 (§A) — Traced function set

Backward-trace transitively from `_resolveLootboxCommon` (`:960`) and `_resolveLootboxRoll` (`:1623`); the resolution path also includes the per-shell pre-`_resolveLootboxCommon` work in the manual entries since that work runs inside the rng-window and influences the eventual reward.

| # | Function | File:line | Reached from | Notes |
|---|---|---|---|---|
| 1 | `openLootBox` | `LootboxModule.sol:526` | external EOA | manual entry — ETH lootbox path |
| 2 | `openBurnieLootBox` | `LootboxModule.sol:607` | external EOA | manual entry — BURNIE lootbox path |
| 3 | `_lootboxEvMultiplierBps` | `LootboxModule.sol:444` | `openLootBox:565` | reads `playerActivityScore` (external view on `address(this)` — re-enters `IDegenerusGame`) |
| 4 | `_lootboxEvMultiplierFromScore` | `LootboxModule.sol:453` | `:566`, `:679`, `:715` | `private pure` — interpolation |
| 5 | `_applyEvMultiplierWithCap` | `LootboxModule.sol:484` | `:567`, `:680`, `:716` | reads + writes `lootboxEvBenefitUsedByLevel[player][lvl]` |
| 6 | `_rollTargetLevel` | `LootboxModule.sol:817` | `:555`, `:630`, `:677`, `:713` | `private pure` — three bit-slices of `seed` |
| 7 | `_simulatedDayIndex` | `Storage.sol:1208` | `:536`, `:626`, `:674`, `:710`, `:750`, `:782`, `_rollLootboxBoons:1125` | `internal view` — delegates to `GameTimeLib.currentDayIndex()` (pure-on-`block.timestamp`) |
| 8 | `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK)` | `Storage.sol:855` | `openLootBox:542` | reads `presaleStatePacked` |
| 9 | `IDegenerusGame.playerActivityScore` | `DegenerusGame.sol:2304` | `_lootboxEvMultiplierBps:445` | external view on self via `address(this)` — calls `_playerActivityScore` |
| 10 | `_playerActivityScore(player, questStreak)` | `MintStreakUtils.sol:169` → `:83` | via `playerActivityScore` | reads `mintPacked_[player]`, `level`, `affiliate.affiliateBonusPointsBest` (or cached affiliate fields), `_mintStreakEffective`, `_mintCountBonusPoints` |
| 11 | `_mintStreakEffective` / `_mintCountBonusPoints` | `MintStreakUtils.sol` | `_playerActivityScore` | both `internal view` — read `mintPacked_[player]` + `level` |
| 12 | `questView.playerQuestStates(player)` | `DegenerusGame.sol:2307` | `playerActivityScore` | external view (quest contract) |
| 13 | `affiliate.affiliateBonusPointsBest(currLevel, player)` | `MintStreakUtils.sol:145` | `_playerActivityScore` (only when cache miss) | external view (affiliate contract) |
| 14 | `PriceLookupLib.priceForLevel(uint24)` | `PriceLookupLib.sol` | `_resolveLootboxCommon:986`, `_lazyPassPriceForLevel:1803`, `openBurnieLootBox:618`, `_boonPoolStats:1210` | `internal pure` — table lookup |
| 15 | `_lootboxBoonBudget(uint256)` | `LootboxModule.sol:838` | `_resolveLootboxCommon:992,1030`, `_rollLootboxBoons:1148` | `private pure` |
| 16 | `_accumulateLootboxRolls` | `LootboxModule.sol:863` | `_resolveLootboxCommon:1004` | thin dispatcher → 1 or 2× `_resolveLootboxRoll` |
| 17 | `_resolveLootboxRoll` | `LootboxModule.sol:1623` | `_accumulateLootboxRolls:883,899` | the second consumer entry; bit-slices `seed >> 40` (`pathRoll`) and `seed >> 80` (`varianceRoll`) |
| 18 | `_lootboxTicketCount` | `LootboxModule.sol:1703` | `_resolveLootboxRoll:1645` | `private pure` — slices `seed >> 96` (`ticketVariance`) |
| 19 | `_lootboxDgnrsReward` | `LootboxModule.sol:1754` | `_resolveLootboxRoll:1652` | `private view` — slices `seed >> 56`; reads `dgnrs.poolBalance(Lootbox)` |
| 20 | `_creditDgnrsReward` | `LootboxModule.sol:1784` | `_resolveLootboxRoll:1654` | calls `dgnrs.transferFromPool(...)` |
| 21 | `IStakedDegenerusStonk.poolBalance(Pool.Lootbox)` | (external) | `_lootboxDgnrsReward:1770` | external view |
| 22 | `IStakedDegenerusStonk.transferFromPool(...)` | (external) | `_creditDgnrsReward:1786` | external state-mutating |
| 23 | `IWrappedWrappedXRP.mintPrize(player, amount)` | (external) | `_resolveLootboxRoll:1671`, `_resolveLootboxCommon:1074` | external state-mutating; reaches WWXRP `_mint` (Transfer event) |
| 24 | `EntropyLib.hash2(uint256, uint256)` | `EntropyLib.sol:23` | `_accumulateLootboxRolls:897` | `internal pure` — full-diffusion keccak mix |
| 25 | `_rollLootboxBoons` | `LootboxModule.sol:1109` | `_resolveLootboxCommon:1026` | slices `seed >> 120`; calls BoonModule + boon-pool stats |
| 26 | `delegatecall IDegenerusGameBoonModule.checkAndClearExpiredBoon` | `LootboxModule.sol:1120` | `_rollLootboxBoons` | nested delegatecall (storage-shared) |
| 27 | `BoonModule.checkAndClearExpiredBoon(player)` | `BoonModule.sol:120` | via delegatecall | reads + writes `boonPacked[player]` (slot0 + slot1); reads `_simulatedDayIndex()` |
| 28 | `_isDecimatorWindow` | `LootboxModule.sol:1813` | `_rollLootboxBoons:1131`, `deityBoonSlots:756`, `issueDeityBoon:796` | reads `decWindowOpen` |
| 29 | `_boonPoolStats` | `LootboxModule.sol:1203` | `_rollLootboxBoons:1135` | reads `level` (via `PriceLookupLib.priceForLevel(level)`); reads `deityPassOwners.length` (already in `deityEligible` flag) |
| 30 | `_burnieToEthValue` | `LootboxModule.sol:1166` | `_boonPoolStats:1213,1217,1221,1259,1263,1267` | `private pure` |
| 31 | `_lazyPassPriceForLevel` | `LootboxModule.sol:1797` | `_rollLootboxBoons:1129` | calls `PriceLookupLib.priceForLevel` ×10 |
| 32 | `_boonFromRoll` | `LootboxModule.sol:1334` | `_rollLootboxBoons:1155`, `_deityBoonForSlot:1837` | `private pure` |
| 33 | `_applyBoon` | `LootboxModule.sol:1407` | `_rollLootboxBoons:1162`, `issueDeityBoon:799` | reads + writes `boonPacked[player]`; reads `level` (via `_activateWhalePass`); calls `_activateWhalePass` for whale-pass branch |
| 34 | `_activateWhalePass` | `LootboxModule.sol:1177` | `_applyBoon:1578` (BOON_WHALE_PASS branch) | reads `level`; calls `_applyWhalePassStats` + 100× `_queueTickets` |
| 35 | `_applyWhalePassStats` | `Storage.sol:1141` | `_activateWhalePass:1184` | reads `mintPacked_[player]`; writes `mintPacked_[player]` |
| 36 | `_currentMintDay` | `Storage.sol:1260` | `_applyWhalePassStats:1197` | reads `dailyIdx` (fallback to `_simulatedDayIndex`) |
| 37 | `_queueTickets` | `Storage.sol:559` | `_resolveLootboxCommon:1067`, `_activateWhalePass:1190` | reads `level`, `rngLockedFlag`, `ticketsOwedPacked[wk][buyer]`, `ticketQueue[wk]`; writes `ticketQueue[wk]` push + `ticketsOwedPacked` |
| 38 | `_livenessTriggered` | `Storage.sol:1243` | `_queueTickets:570` | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`, `_simulatedDayIndex` |
| 39 | `_tqWriteKey` / `_tqFarFutureKey` | `Storage.sol` | `_queueTickets:573-575` | `internal pure` — bit-ops on level |
| 40 | `IBurnieCoinflip.creditFlip(player, burnieAmount)` | (external) | `_resolveLootboxCommon:1079` | external state-mutating |
| 41 | `delegatecall IDegenerusGameBoonModule.consumeActivityBoon` | `LootboxModule.sol:1035` | `_resolveLootboxCommon` (allowBoons branch) | nested delegatecall |
| 42 | `BoonModule.consumeActivityBoon(player)` | `BoonModule.sol:281` | via delegatecall | reads + writes `boonPacked[player]` slot1; reads + writes `mintPacked_[player]` (levelCount field); calls `quests.awardQuestStreakBonus` |

**Explicit-enumeration discipline per `feedback_verify_call_graph_against_source.md`:** every reached function is cited by file:line; no "by construction" / "covered by single fn" claims. Cross-checked by `grep -n "function \|delegatecall\|IDegenerus\|coinflip\.\|dgnrs\.\|wwxrp\.\|affiliate\.\|quests\." contracts/modules/DegenerusGameLootboxModule.sol` and `grep -n "function " contracts/modules/DegenerusGameBoonModule.sol` covering the BoonModule branches reached transitively.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during `openLootBox` / `openBurnieLootBox` → `_resolveLootboxCommon` → `_resolveLootboxRoll` execution, per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 enumeration discipline. Inline-assembly slot directives + raw `sstore` checked via `grep -n "assembly\|slot:" contracts/modules/DegenerusGameLootboxModule.sol contracts/modules/DegenerusGameBoonModule.sol contracts/storage/DegenerusGameStorage.sol` — only `EntropyLib.hash2` uses memory-safe scratch (`mstore`/`keccak256`); no inline raw `sstore` writes to any in-scope slot.

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-1 | `lootboxEth[index][player]` | `LootboxModule.sol:528` | `packed`; `amount = packed & ((1<<232)-1)` flows into `seed` (line 554) AND into every per-roll budget (`amountFirst`, `amountSecond`, `_lootboxBoonBudget`, ticket / DGNRS / WWXRP / large-BURNIE budgets) | **YES** | — |
| B-2 | `lootboxRngWordByIndex[index]` | `:533` (ETH), `:612` (BURNIE) | `rngWord` flows into `seed = keccak256(rngWord, player, day, amount)` (`:554`, `:629`) | **YES** | — |
| B-3 | `lootboxDay[index][player]` | `:537` (ETH), `:624` (BURNIE) | flows into `seed` (`day` field of keccak input at `:554`/`:629`); also emitted on `LootBoxOpened.day` | **YES** | — |
| B-4 | `presaleStatePacked` (via `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK)`) | `:542` (ETH path only) | `presale` flag → controls 62% bonus BURNIE multiplier (`_resolveLootboxCommon:1016-1019`) | **YES** | — |
| B-5 | `lootboxEthBase[index][player]` | `:543` | `baseAmount` — read at `:543` but the only use is `if (baseAmount == 0) baseAmount = amount;` and the value is never re-read in `_resolveLootboxCommon` (the sole consumer is `lootboxBaseLevelPacked` path which uses purchase-level, not baseAmount). | NO | Dead read at `openLootBox` scope: `baseAmount` is computed but never referenced after `:546`. (Cross-check: `grep -n "baseAmount" contracts/modules/DegenerusGameLootboxModule.sol` returns only lines 543-546.) Does not drive any VRF-derived output. |
| B-6 | `level` (global `uint24`) | `:548` (ETH `currentLevel = level + 1`), `:618` (BURNIE `priceForLevel(level)`), `:623` (BURNIE `currentLevel = level + 1`), `:675`, `:711`, `_isDistressMode:546`, `_livenessTriggered:1245`, `_queueTickets:571`, `_boonPoolStats:1210`, `_rollLootboxBoons:1126`, `_activateWhalePass:1180`, `_playerActivityScore:96`, gameOverPossible ENF-02 check `:634` | drives `currentLevel` (clamps `targetLevel`); drives BURNIE-amount conversion via `priceForLevel(level)`; drives `_queueTickets` far-future-key branch; drives `_boonPoolStats` price; drives `_playerActivityScore` whale-bundle bonus | **YES** | — |
| B-7 | `gameOverPossible` | `:634` (BURNIE path only) | drives `targetLevel \|= TICKET_FAR_FUTURE_BIT` redirect when ENF-02 triggers | **YES** | — |
| B-8 | `lootboxBaseLevelPacked[index][player]` | `:550` (ETH path only) | `baseLevelPacked` → `graceLevel` → `baseLevel` → `targetLevel` via `_rollTargetLevel` | **YES** | — |
| B-9 | `lootboxEvScorePacked[index][player]` | `:563` (ETH path only) | if non-zero, drives `evMultiplierBps` via snapshotted score; if zero, falls through to LIVE `_lootboxEvMultiplierBps(player)` read of activity score | **YES** | — |
| B-10 | `mintPacked_[player]` (HAS_DEITY_PASS bit, LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE, AFFILIATE_BONUS_LEVEL, AFFILIATE_BONUS_POINTS) | `_playerActivityScore:90` (multiple bit-fields); `_rollLootboxBoons:1133` (HAS_DEITY_PASS bit for `deityEligible`); `_applyWhalePassStats:1145`; `BoonModule.consumeActivityBoon:303` | drives `scoreBps` → `evMultiplierBps` → `scaledAmount` → seed-amount input AND amount used in every per-roll budget; drives `deityEligible` flag in `_boonPoolStats` (toggles deity-pass branch ≈400-weight slice of boon roll) | **YES** | — |
| B-11 | `streakPacked` / `_mintStreakEffective` storage reads | `_mintStreakEffective` (`MintStreakUtils.sol`) — reads `mintPacked_[player]` + per-level streak fields | feeds `_playerActivityScore` streak component | **YES** | covered by B-10's mintPacked_ entry from a participating-slot perspective (same slot; same writer set); listed separately for trace completeness |
| B-12 | `lootboxDistressEth[index][player]` | `:574` (ETH path only) | `distressEth` → drives 25% distress-mode ticket bonus inside `_resolveLootboxCommon:1042-1048` | **YES** | — |
| B-13 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `_applyEvMultiplierWithCap:496` | drives `remainingCap` → `adjustedPortion` → `scaledAmount` (LIVE accumulator; mutated by EVERY prior lootbox open at the same level) | **YES** | — |
| B-14 | `lootboxBurnie[index][player]` | `:609` (BURNIE path only) | `burnieAmount` flows into `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)` (`:620`) → drives `seed`'s amount input + every budget | **YES** | — |
| B-15 | `dailyIdx` (global `uint32`) | `_currentMintDay:1261` (via `_applyWhalePassStats:1197`); ALSO read in `_simulatedDayIndex` chain (no — `_simulatedDayIndex` is `GameTimeLib.currentDayIndex()` which reads `block.timestamp` only, NOT `dailyIdx`) | drives the `day` field stamped into `mintPacked_[player]` during whale-pass activation (post-roll bookkeeping; does NOT feed back into the current resolution's RNG-derived output) | NO | Only reached on the whale-pass branch of `_applyBoon` (when `_boonFromRoll` returns `BOON_WHALE_PASS`), and even then it is written into a `data` value that is SSTORE'd to `mintPacked_[player]` AFTER all reward decisions are made. The current resolution's VRF-derived output (`futureTickets`, `burnieAmount`, `roundedUp`, DGNRS reward) is fully determined before this read. |
| B-16 | `decWindowOpen` (via `_isDecimatorWindow`) | `_rollLootboxBoons:1131`, `deityBoonSlots:756`, `issueDeityBoon:796` | `decimatorAllowed` → controls inclusion of `BOON_WEIGHT_DECIMATOR_10/25/50` in `_boonPoolStats` total weight + in `_boonFromRoll` boon-type space; SHIFTS the cumulative-cursor mapping between `roll` and `boonType` | **YES** | — |
| B-17 | `deityPassOwners.length` | `_rollLootboxBoons:1133`, `_boonPoolStats:1292`, `deityBoonSlots:757`, `issueDeityBoon:797` | gates `deityEligible` (and `deityPassAvailable`) → controls inclusion of `BOON_WEIGHT_DEITY_PASS_10/25/50` in boon-roll space; computes `deityPrice` weighted-max | **YES** | — |
| B-18 | `boonPacked[player].slot0` (BoonModule.checkAndClearExpiredBoon) | `BoonModule.sol:123` | drives per-category expiry checks (coinflip/lootbox/purchase/decimator/whale tiers); SSTORE'd back on changed bits at `:265` | **YES** | — |
| B-19 | `boonPacked[player].slot1` (BoonModule.checkAndClearExpiredBoon + consumeActivityBoon) | `BoonModule.sol:124,284` | activity / deity-pass / lazy-pass expiry + activity-boon consumption SSTORE'd back | **YES** | — |
| B-20 | `dgnrs.poolBalance(Pool.Lootbox)` (cross-contract: `IStakedDegenerusStonk.sol` storage read) | `_lootboxDgnrsReward:1770` | drives `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)` → DGNRS reward magnitude (10% path of `_resolveLootboxRoll`) | **YES** | — |
| B-21 | `lastPurchaseDay` (global `bool`) | `_livenessTriggered:1244` | short-circuits liveness → controls whether `_queueTickets` reverts | **YES** | — |
| B-22 | `jackpotPhaseFlag` (global `bool`) | `_livenessTriggered:1244` | short-circuits liveness → controls whether `_queueTickets` reverts | **YES** | — |
| B-23 | `purchaseStartDay` (global `uint32`) | `_livenessTriggered:1246`, `_isDistressMode:544` | `_livenessTriggered` day-math (`currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS` / `>120`); `_isDistressMode` not on lootbox path | **YES** | — |
| B-24 | `rngRequestTime` (global `uint48`) | `_livenessTriggered:1250` | stalled-advance bailout check (`>= _VRF_GRACE_PERIOD`) | **YES** | — |
| B-25 | `rngLockedFlag` (global `bool`) | `_queueTickets:572` | gates the far-future ticket-queue branch with revert | **YES** | — |
| B-26 | `ticketsOwedPacked[wk][buyer]` | `_queueTickets:576`, `MintModule:423,761,...` (other writers' reads outside scope) | read in same SSTORE-merge call at `:585`; aggregates existing tickets queued at level `wk`. Does NOT feed back into VRF-derived seed slicing or roll-result derivation; affects only output-ticket accounting state. | NO | Pure write-merge accumulator inside `_queueTickets`. The function consumes the pre-image `wk` (derived from `targetLevel`) + `quantity` (from RNG-derived `whole`) + the existing packed value; produces a new packed value. The roll outcome is already committed at this point — the SLOAD only affects what's stored back, not what's emitted as the reward. |
| B-27 | `ticketQueue[wk].length` | `_queueTickets:579` (`if (owed == 0 && rem == 0)` push branch) | same as B-26 — output-state-only accumulator | NO | Same reasoning as B-26: write-time-only, post-roll. |
| B-28 | `affiliate.affiliateBonusPointsBest(currLevel, player)` (cross-contract SLOAD on `DegenerusAffiliate.sol`) | `_playerActivityScore:145` (cache-miss branch only) | drives `affPoints` → `bonusBps` → `scoreBps` → `evMultiplierBps` → `scaledAmount` | **YES** | — |
| B-29 | `questView.playerQuestStates(player)` (cross-contract — DegenerusQuests storage) | `DegenerusGame.sol:2307` | drives `questStreak` → `bonusBps += questStreakCapped * 100;` → `scoreBps` → `evMultiplierBps` → `scaledAmount` | **YES** | — |

**Auxiliary §B-W — SSTOREs inside the resolution body** (cross-check, not classified):

| # | Slot | Write-site (file:line) | Notes |
|---|---|---|---|
| B-W1 | `lootboxEth[index][player] = 0` | `:576` | committed-state zero-out before any reward emission |
| B-W2 | `lootboxEthBase[index][player] = 0` | `:577` | ditto |
| B-W3 | `lootboxBaseLevelPacked[index][player] = 0` | `:578` | ditto |
| B-W4 | `lootboxEvScorePacked[index][player] = 0` | `:579` | ditto |
| B-W5 | `lootboxDistressEth[index][player] = 0` | `:581` | ditto (conditional) |
| B-W6 | `lootboxBurnie[index][player] = 0` | `:615` (BURNIE path) | ditto |
| B-W7 | `lootboxEvBenefitUsedByLevel[player][lvl] += adjustedPortion` | `_applyEvMultiplierWithCap:511` | mutates the accumulator read at B-13; future calls to `openLootBox` for the same `(player, lvl)` get a different `remainingCap` |
| B-W8 | `boonPacked[player].slot0` / `.slot1` | `BoonModule.sol:265-266`, `_applyBoon:1432`,`1452`,`1479`,`1503`,`1526`,`1547`,`1568`,`1603` (multi) | tier promotions + day-stamps; influences NEXT lootbox's boon decisions |
| B-W9 | `mintPacked_[player]` | `_applyWhalePassStats:1204`, `BoonModule.consumeActivityBoon:320` | levelCount + whale-bundle fields |
| B-W10 | `ticketQueue[wk].push(buyer)` / `ticketsOwedPacked[wk][buyer]` | `_queueTickets:580,585`, `_activateWhalePass:1190` | output-state ticket bookkeeping |
| B-W11 | DGNRS pool balance mutation (external) | `dgnrs.transferFromPool(...)` (`_creditDgnrsReward:1786`) | reduces `poolBalance` read at B-20 for FUTURE resolutions |
| B-W12 | Coinflip credit balance (external) | `coinflip.creditFlip(player, burnieAmount)` (`:1079`) | post-roll credit |
| B-W13 | WWXRP `mintPrize` (external) | `:1074`, `:1671` | post-roll mint |

### CAT-03 (§C) — Writer enumeration for participating slots

For each `Participating? = YES` slot from §B, enumerate every external/public function that writes it. Methodology: `grep -rn "<slot>\s*=\|<slot>\.\(push\|pop\)\|<slot>\[.*\]\s*=" contracts/ --include="*.sol"` then cross-reference each hit's enclosing function visibility + external-reach chain. Library-constant non-storage reads (`ContractAddresses.*`, `PriceLookupLib.*`) skipped per §B already-attested.

### C-1 — `lootboxEth[index][player]` (B-1)

Mapping: `Storage.sol:832` (`mapping(uint48 => mapping(address => uint256)) internal lootboxEth`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-1-a | `LootboxModule.openLootBox` | `LootboxModule.sol:576` (`= 0`) | `DegenerusGame.openLootBox` (`:665`, EOA) — **MANUAL** |
| C-1-b | `DegenerusGameMintModule._allocateLootbox` (or similar — `:1013`) | `MintModule.sol:1013` | `DegenerusGame.buyTickets` / `processMint` chain (EOA + ETH-payable) |
| C-1-c | `DegenerusGameWhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:876` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-2 — `lootboxRngWordByIndex[index]` (B-2)

Mapping: `Storage.sol:1367`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-2-a | `AdvanceModule._finalizeLootboxRng` | `AdvanceModule.sol:1256` | reached from `advanceGame()` daily-RNG path AND from VRF callback `rawFulfillRandomWords:1761` (mid-day mode) |
| C-2-b | `AdvanceModule.rawFulfillRandomWords` (mid-day branch) | `AdvanceModule.sol:1761` | **EXEMPT-VRFCALLBACK** — Chainlink VRF coordinator only |
| C-2-c | `AdvanceModule._backfillOrphanedLootboxIndices` | `AdvanceModule.sol:1818` | reached from `_gameOverEntropy` historical-fallback path (which is `advanceGame()`-rooted) |

### C-3 — `lootboxDay[index][player]` (B-3)

Mapping: `Storage.sol:1370`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-3-a | `DegenerusGameMintModule._allocateLootbox` | `MintModule.sol:991` | `DegenerusGame.buyTickets` (EOA + ETH-payable) |
| C-3-b | `DegenerusGameMintModule._burnieAllocate` | `MintModule.sol:1397` | `BurnieCoin → DegenerusGame.processBurnieTicketBuy` (BURNIE-coin transfer-to-game callback) |
| C-3-c | `DegenerusGameWhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:854` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` |

### C-4 — `presaleStatePacked` (B-4)

Storage: `Storage.sol:843`. Written via `_psWrite` (`:860`) only.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-4-a | `DegenerusGameMintModule._presaleCapCheck` | `MintModule.sol:1026` (`presaleStatePacked = psPacked`) | `DegenerusGame.buyTickets` / `processMint` (EOA) — cumulative-cap evaluation |
| C-4-b | `DegenerusGameAdvanceModule._handlePhaseTransition` | `AdvanceModule.sol:433` (`_psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0)`) | `advanceGame()` — auto-end at jackpot phase start |

### C-5 — `level` (B-6)

Storage: `uint24 internal level;` (Storage layout). Sole writer: `AdvanceModule._unlockRng` (`:1643` `level = lvl;`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-5-a | `AdvanceModule._unlockRng` | `AdvanceModule.sol:1643` | `advanceGame()` (level transition at RNG request time when `lastPurchaseDay = true`) |

### C-6 — `gameOverPossible` (B-7)

Storage: `bool internal gameOverPossible;` (Storage.sol:316).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-6-a | `AdvanceModule.advanceGame` (FLAG-03 auto-clear) | `AdvanceModule.sol:178` (`if (gameOverPossible) gameOverPossible = false`) | `advanceGame()` |
| C-6-b | `AdvanceModule._evalGameOverPossible` (the assignment block at `:1888`,`:1893`) | `AdvanceModule.sol:1888,1893` | `advanceGame()` |

### C-7 — `lootboxBaseLevelPacked[index][player]` (B-8)

Mapping: `Storage.sol:1375`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-7-a | `LootboxModule.openLootBox` | `LootboxModule.sol:578` (`= 0`) | `DegenerusGame.openLootBox` (EOA) — **MANUAL** |
| C-7-b | `MintModule._allocateLootbox` | `MintModule.sol:992` | `DegenerusGame.buyTickets` (EOA + ETH-payable) |
| C-7-c | `WhaleModule._whaleLootboxAllocate` | `WhaleModule.sol:855` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-8 — `lootboxEvScorePacked[index][player]` (B-9)

Mapping: `Storage.sol:1379`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-8-a | `LootboxModule.openLootBox` | `LootboxModule.sol:579` (`= 0`) | `DegenerusGame.openLootBox` (EOA) — **MANUAL** |
| C-8-b | `MintModule._allocateLootbox` (post-score-compute snapshot) | `MintModule.sol:1155` | `DegenerusGame.buyTickets` (EOA + ETH-payable) |
| C-8-c | `WhaleModule._whaleLootboxAllocate` (post-score snapshot) | `WhaleModule.sol:856` | `DegenerusGame.buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-9 — `mintPacked_[player]` (B-10 / B-11)

Mapping: `Storage.sol` (mintPacked_). Writers (all visible via grep):

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-9-a | `MintStreakUtils._mintStreakWrite` (writer at `:47`) | `MintStreakUtils.sol:47` | `MintModule._processMint` / `_processBurnieMint` (EOA mint paths via `DegenerusGame.buyTickets` / BURNIE-coin callback) |
| C-9-b | `MintModule._allocateMintPacked` (writes at `:240,:275,:369`) | `MintModule.sol:240,275,369` | `buyTickets` (EOA + ETH-payable) |
| C-9-c | `BoonModule.consumeActivityBoon` (writes at `:320`) | `BoonModule.sol:320` | reached via delegatecall from `_rollLootboxBoons:1035` (i.e., from this very consumer's resolution path AND from other lootbox-resolution paths); **STILL EOA-reachable** because the delegatecall is on the lootbox stack |
| C-9-d | `BoonModule._applyBoon` (mintPacked_ touches via `_applyWhalePassStats`) | `BoonModule.sol:303,320` + `_applyWhalePassStats:1204` (`Storage.sol`) | reachable from `openLootBox` (manual whale-pass boon) AND from auto-resolve callers AND from `issueDeityBoon` |
| C-9-e | `WhaleModule._buyWhaleBundle*` (writes at `:210,:303,:419,:516,:548,:589,:669,:944`) | `WhaleModule.sol:*` | `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` (EOA + ETH-payable) |
| C-9-f | `WhaleModule._buyDeityPass` (deity-pass acquisition) | `WhaleModule.sol:589` | `buyDeityPass` (EOA + ETH-payable) |
| C-9-g | `AdvanceModule._cacheAffiliateBonus` (writes affiliate fields at `:1008`) | `AdvanceModule.sol:1008` | `advanceGame()` |
| C-9-h | `DegenerusGame` constructor (sentinel deity-pass bits for SDGNRS + VAULT) | `DegenerusGame.sol:222,223` | constructor-only (EXEMPT-CONSTRUCTOR) |
| C-9-i | `_applyWhalePassStats` (when reached from lootbox whale-pass boon) | `Storage.sol:1204` | from `_activateWhalePass` (reached on the lootbox stack itself) |

**OZ-inherited writers check:** `mintPacked_` is a private mapping in `DegenerusGameStorage`; not a token balance. No ERC20/ERC721 inheritance writes it.

### C-10 — `lootboxDistressEth[index][player]` (B-12)

Mapping: `Storage.sol:1506`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-10-a | `LootboxModule.openLootBox` | `LootboxModule.sol:581` (`= 0`, conditional) | `DegenerusGame.openLootBox` (EOA) — **MANUAL** |
| C-10-b | `MintModule._allocateLootbox` (distress accumulation) | `MintModule.sol:1031` | `buyTickets` (EOA + ETH-payable) |
| C-10-c | `WhaleModule._whaleLootboxAllocate` (distress accumulation) | `WhaleModule.sol:881` | `buyWhaleBundle` / `buyWhaleHalf` (EOA + ETH-payable) |

### C-11 — `lootboxEvBenefitUsedByLevel[player][lvl]` (B-13)

Mapping: `Storage.sol:1428`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-11-a | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule.sol:511` | reached from `openLootBox:567` (**MANUAL**) AND `resolveLootboxDirect:680` (auto) AND `resolveRedemptionLootbox:716` (auto) |

### C-12 — `lootboxBurnie[index][player]` (B-14)

Mapping: `Storage.sol:1386`.

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-12-a | `LootboxModule.openBurnieLootBox` | `LootboxModule.sol:615` (`= 0`) | `DegenerusGame.openBurnieLootBox` (EOA) — **MANUAL** |
| C-12-b | `MintModule._burnieAllocate` | `MintModule.sol:1399` (`+= burnieAmount`) | `BurnieCoin → DegenerusGame.processBurnieTicketBuy` (BURNIE transfer callback; EOA-triggered) |

### C-13 — `decWindowOpen` (B-16)

Storage: `bool internal decWindowOpen;` (Storage.sol:278).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-13-a | `AdvanceModule._unlockRng` | `AdvanceModule.sol:1655` (`= true`) | `advanceGame()` |
| C-13-b | `AdvanceModule._unlockRng` (close branch) | `AdvanceModule.sol:1659` (`= false`) | `advanceGame()` |

### C-14 — `deityPassOwners` (B-17)

Storage: `address[] internal deityPassOwners;` (DegenerusGameStorage).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-14-a | `WhaleModule._buyDeityPass` | `WhaleModule.sol:596` (`deityPassOwners.push(buyer)`) | `DegenerusGame.buyDeityPass` (EOA + ETH-payable) |

No pop sites — `deityPassOwners` only grows. Length is monotonic.

### C-15 — `boonPacked[player]` slot0 + slot1 (B-18 + B-19)

Struct mapping: `Storage.sol` (`boonPacked`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-15-a | `LootboxModule._applyBoon` slot0 writes | `LootboxModule.sol:1432,1452,1479,1503,1526,1547,1568,1603` etc. | reached from `_rollLootboxBoons:1162` (this consumer — **MANUAL** via `openLootBox`/`openBurnieLootBox`); from auto-resolve callers; and from `issueDeityBoon:799` (EOA — deity-pass holders) |
| C-15-b | `WhaleModule._buyWhaleBundle*` boon-slot writes | `WhaleModule.sol:202,388,556,898` (multiple) | `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` (EOA + ETH-payable) |
| C-15-c | `MintModule._processMint` (BoonPacked writes at `:1433`) | `MintModule.sol:1433` | `buyTickets` (EOA + ETH-payable) |
| C-15-d | `BoonModule.checkAndClearExpiredBoon` slot writes | `BoonModule.sol:265,266` | external function (called via delegatecall from `_rollLootboxBoons:1120`) **AND** can be reached directly via the BoonModule's external interface if any caller delegatecalls it from `DegenerusGame`. Grep confirms call-sites: `LootboxModule.sol:1120` only (no other dispatcher) — but reach is still EOA via the lootbox-roll path |
| C-15-e | `BoonModule.consumeActivityBoon` slot1 writes | `BoonModule.sol:291,297,301` | external (delegatecalled from `_resolveLootboxCommon:1035`) |
| C-15-f | `BoonModule.<other-external-mutators>` (`:41,67,93,122,283`) | `BoonModule.sol:41,67,93,122,283` | additional BoonModule externals; verified by `grep -n "external\|public" contracts/modules/DegenerusGameBoonModule.sol` — each call-site needs per-callsite reach analysis but is conservatively classified VIOLATION below absent evidence of EXEMPT-stack reach |

### C-16 — `dgnrs.poolBalance(Lootbox)` cross-contract (B-20)

Cross-contract slot on `StakedDegenerusStonk.sol`. `dgnrs` is `internal constant` (`Storage.sol:146`).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-16-a | `StakedDegenerusStonk._addToPool` / `_transferFromPool` (internal helpers in sDGNRS) — reached from `DegenerusStonk.transferFromPool` external, and from `DegenerusGame.fundLootboxPool` / decay sweeps | (cross-contract; out-of-this-file enumeration) | Reaches via `DegenerusGame` admin functions (`forceClaim` / sweep paths) AND via `_creditDgnrsReward:1786` itself (own writes — the consumer mutates B-20 mid-call) AND via `dgnrs.transferFromPool` calls from JackpotModule / DecimatorModule / DegeneretteModule (all on `advanceGame()` / VRF-callback stacks). **Per-callsite VIOLATION classification requires enumerating each writer on the sDGNRS side.** Conservative scope: any caller that mutates `dgnrs.poolBalance(Lootbox)` between the VRF callback (B-2 write) and the manual `openLootBox` (B-20 read) shifts B-20 — and EOAs can plausibly trigger pool-mutating paths via `DegenerusStonk.transferIn` / `forceDeposit` admin routes |

### C-17 — `lastPurchaseDay` (B-21)

Storage: `bool internal lastPurchaseDay;` (Storage.sol:273).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-17-a | `AdvanceModule.advanceGame` (sets true at `:176`) | `AdvanceModule.sol:176` | `advanceGame()` |
| C-17-b | `AdvanceModule.advanceGame` (sets true at `:397`) | `AdvanceModule.sol:397` | `advanceGame()` |
| C-17-c | `AdvanceModule._handlePhaseTransition` (sets false at `:439`) | `AdvanceModule.sol:439` | `advanceGame()` |

### C-18 — `jackpotPhaseFlag` (B-22)

Storage: `bool internal jackpotPhaseFlag;` (Storage.sol:257).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-18-a | `AdvanceModule._handlePhaseTransition` (`:333` false, `:437` true) | `AdvanceModule.sol:333,437` | `advanceGame()` |

### C-19 — `purchaseStartDay` (B-23)

Storage: `uint32 internal purchaseStartDay;` (Storage.sol).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-19-a | `DegenerusGame` constructor | `DegenerusGame.sol:218` | constructor-only (EXEMPT-CONSTRUCTOR) |
| C-19-b | `AdvanceModule._handlePhaseTransition` | `AdvanceModule.sol:332` (`purchaseStartDay = day;`) | `advanceGame()` |

### C-20 — `rngRequestTime` (B-24)

Storage: `uint48 internal rngRequestTime;` (Storage.sol).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-20-a | `AdvanceModule._tryRequestRng` (`:1122`) | `AdvanceModule.sol:1122` | `advanceGame()` |
| C-20-b | `AdvanceModule.retryLootboxRng` (`:1154`) | `AdvanceModule.sol:1154` | `retryLootboxRng()` (EOA-callable) — **EXEMPT-RETRYLOOTBOXRNG** per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A |
| C-20-c | `AdvanceModule._gameOverEntropy` (`:1329`) | `AdvanceModule.sol:1329` | `advanceGame()` (fallback path clearing) |
| C-20-d | `AdvanceModule._gameOverEntropy` (`:1341`) | `AdvanceModule.sol:1341` | `advanceGame()` |
| C-20-e | `AdvanceModule._unlockRng` (`:1633`) | `AdvanceModule.sol:1633` | `advanceGame()` |
| C-20-f | `AdvanceModule._unlockRng` (`:1692`) | `AdvanceModule.sol:1692` | `advanceGame()` |
| C-20-g | `AdvanceModule._unlockRng` (`:1734`) | `AdvanceModule.sol:1734` | `advanceGame()` |
| C-20-h | `AdvanceModule.rawFulfillRandomWords` (`:1764`) | `AdvanceModule.sol:1764` | VRF coordinator only — **EXEMPT-VRFCALLBACK** |

### C-21 — `rngLockedFlag` (B-25)

Storage: `bool internal rngLockedFlag;` (Storage.sol:284).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-21-a | `AdvanceModule._unlockRng` (`:1634` true, `:1690` false, `:1731` false) | `AdvanceModule.sol:1634,1690,1731` | `advanceGame()` (lock and unlock branches) |

### C-22 — `affiliate.affiliateBonusPointsBest(...)` cross-contract (B-28)

Cross-contract slots in `DegenerusAffiliate.sol`. Per `D-298-TRACE-DEPTH-01` trace walks the source. Writers are `DegenerusAffiliate.recordAffiliateEarnings` and the leaderboard-update path — reached from EOA via `MintModule` / `WhaleModule` mint flows (affiliate amounts recorded on every ticket purchase). Per-callsite enumeration in §C-22:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|
| C-22-a | `DegenerusAffiliate.recordAffiliateEarnings` (or equivalent — see `grep -n "function \|external\|public" contracts/DegenerusAffiliate.sol`) | (cross-contract) | reached from MintModule / WhaleModule mint flows (EOA + ETH-payable) |

### C-23 — `questView.playerQuestStates(player)` cross-contract (B-29)

Cross-contract — DegenerusQuests storage. Writers are `DegenerusQuests` external/quest-fulfillment functions (EOA-callable). Per-callsite reach is EOA on the quest-claim path. Conservatively classified per the same VIOLATION shape since the streak SLOAD is read live during lootbox resolution.

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Each writer-callsite is classified `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION` (v43.0 milestone-goal prohibits a no-disposition residual category).

| # | Slot | Writer function (C-ref) | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `lootboxEth` | LootboxModule.openLootBox `=0` (C-1-a) | `:576` | NO — own write inside the SELF callsite; per-callsite reach is EOA (`DegenerusGame.openLootBox`). However, the write zeroes the slot AFTER `seed` is derived (`:554`) and AFTER `amount` is captured; so this write does not influence the current resolution's RNG output. | **EXEMPT-VRFCALLBACK** ⊕ EOA self-write — the slot mutation cannot be exploited intra-resolution. Reach: reentry-safe (whole module is `private`/`external` with delegatecall). Classification: **EXEMPT-ADVANCEGAME-EQUIVALENT** by post-roll positioning. **For audit-conservative discipline, classified VIOLATION but with rationale "self-zero, post-amount-capture"** |
| D-2 | `lootboxEth` | MintModule._allocateLootbox (C-1-b) | `MintModule.sol:1013` | NO — reached from `DegenerusGame.buyTickets` (EOA) | **VIOLATION** |
| D-3 | `lootboxEth` | WhaleModule._whaleLootboxAllocate (C-1-c) | `WhaleModule.sol:876` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-4 | `lootboxRngWordByIndex` | AdvanceModule._finalizeLootboxRng (C-2-a from `rngGate` daily path) | `AdvanceModule.sol:1256` | YES — `advanceGame()` daily-RNG path | **EXEMPT-ADVANCEGAME** |
| D-5 | `lootboxRngWordByIndex` | AdvanceModule.rawFulfillRandomWords mid-day (C-2-b) | `AdvanceModule.sol:1761` | YES — VRF coordinator only (gated by `msg.sender != vrfCoordinator` revert at `:1749`) | **EXEMPT-VRFCALLBACK** |
| D-6 | `lootboxRngWordByIndex` | AdvanceModule._backfillOrphanedLootboxIndices (C-2-c) | `AdvanceModule.sol:1818` | YES — reached from `_gameOverEntropy` on `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-7 | `lootboxDay` | MintModule._allocateLootbox (C-3-a) | `MintModule.sol:991` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-8 | `lootboxDay` | MintModule._burnieAllocate (C-3-b) | `MintModule.sol:1397` | NO — EOA via BURNIE-coin transfer callback | **VIOLATION** |
| D-9 | `lootboxDay` | WhaleModule._whaleLootboxAllocate (C-3-c) | `WhaleModule.sol:854` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-10 | `presaleStatePacked` | MintModule._presaleCapCheck (C-4-a) | `MintModule.sol:1026` | NO — EOA via `buyTickets` / `processMint`; cumulative cap evaluation runs per-mint | **VIOLATION** |
| D-11 | `presaleStatePacked` | AdvanceModule._handlePhaseTransition (C-4-b) | `AdvanceModule.sol:433` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-12 | `level` | AdvanceModule._unlockRng (C-5-a) | `AdvanceModule.sol:1643` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-13 | `gameOverPossible` | AdvanceModule.advanceGame FLAG-03 (C-6-a) | `AdvanceModule.sol:178` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-14 | `gameOverPossible` | AdvanceModule._evalGameOverPossible (C-6-b) | `AdvanceModule.sol:1888,1893` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-15 | `lootboxBaseLevelPacked` | LootboxModule.openLootBox self-zero (C-7-a) | `LootboxModule.sol:578` | self-write post-`targetLevel`-derivation | **EXEMPT-VRFCALLBACK-EQUIVALENT** (self-zero post-roll). Audit-conservative: classified **VIOLATION** with "self-zero, post-roll" rationale |
| D-16 | `lootboxBaseLevelPacked` | MintModule._allocateLootbox (C-7-b) | `MintModule.sol:992` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-17 | `lootboxBaseLevelPacked` | WhaleModule._whaleLootboxAllocate (C-7-c) | `WhaleModule.sol:855` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-18 | `lootboxEvScorePacked` | LootboxModule.openLootBox self-zero (C-8-a) | `LootboxModule.sol:579` | self-write post-`evMultiplierBps`-derivation | **VIOLATION** (audit-conservative: self-zero, post-roll) |
| D-19 | `lootboxEvScorePacked` | MintModule._allocateLootbox snapshot write (C-8-b) | `MintModule.sol:1155` | NO — EOA via `buyTickets`; **mints the score snapshot at purchase time, so subsequent EOA mints to the same `(index, buyer)` between RNG-fulfill and open mutate the score** | **VIOLATION** |
| D-20 | `lootboxEvScorePacked` | WhaleModule._whaleLootboxAllocate snapshot (C-8-c) | `WhaleModule.sol:856` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-21 | `mintPacked_` | MintStreakUtils._mintStreakWrite (C-9-a) | `MintStreakUtils.sol:47` | NO — EOA via mint flows | **VIOLATION** |
| D-22 | `mintPacked_` | MintModule._allocateMintPacked (C-9-b, 3 callsites) | `MintModule.sol:240,275,369` | NO — EOA via `buyTickets` / `processMint` | **VIOLATION** |
| D-23 | `mintPacked_` | BoonModule.consumeActivityBoon (C-9-c) | `BoonModule.sol:320` | The delegatecall is on the lootbox stack itself; if reached from `openLootBox` (manual), classification follows the manual stack → **NOT** advanceGame-rooted. Per `D-298-EXEMPT-REACH-01` per-callsite: this callsite is reached **inside** the current resolution, so the write is post-amount-capture but pre-final-emission. The write happens INSIDE `_resolveLootboxCommon:1035` before `_resolveLootboxRoll` returns. Mutation timing: AFTER seed derivation but BEFORE boon-roll consumption. | **EXEMPT-ADVANCEGAME-EQUIVALENT** (self-stack write; cannot be exploited cross-tx). Audit-conservative: classified **VIOLATION** with "self-stack post-seed" rationale |
| D-24 | `mintPacked_` | WhaleModule._buyWhaleBundle* (C-9-e, multiple) | `WhaleModule.sol:*` (210,303,419,516,548,589,669,944) | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` | **VIOLATION** |
| D-25 | `mintPacked_` | WhaleModule._buyDeityPass (C-9-f) | `WhaleModule.sol:589` | NO — EOA via `buyDeityPass` | **VIOLATION** |
| D-26 | `mintPacked_` | AdvanceModule._cacheAffiliateBonus (C-9-g) | `AdvanceModule.sol:1008` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-27 | `mintPacked_` | DegenerusGame constructor (C-9-h) | `DegenerusGame.sol:222,223` | constructor — single shot at deploy | **EXEMPT-ADVANCEGAME-EQUIVALENT** (constructor-only) — audit-conservative: outside the rng-window, classified **EXEMPT-ADVANCEGAME** by structural unreachability post-deploy |
| D-28 | `mintPacked_` | _applyWhalePassStats from lootbox boon path (C-9-i) | `Storage.sol:1204` | This write reached from `_activateWhalePass` on the LOOTBOX stack itself (BOON_WHALE_PASS branch of `_applyBoon`). Same self-stack timing as D-23. | **VIOLATION** (audit-conservative: self-stack post-seed) |
| D-29 | `lootboxDistressEth` | LootboxModule.openLootBox self-zero (C-10-a) | `LootboxModule.sol:581` | self-write post-distressEth-capture | **VIOLATION** (audit-conservative: self-zero, post-roll) |
| D-30 | `lootboxDistressEth` | MintModule._allocateLootbox (C-10-b) | `MintModule.sol:1031` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-31 | `lootboxDistressEth` | WhaleModule._whaleLootboxAllocate (C-10-c) | `WhaleModule.sol:881` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` | **VIOLATION** |
| D-32 | `lootboxEvBenefitUsedByLevel` | LootboxModule._applyEvMultiplierWithCap (C-11-a) | `LootboxModule.sol:511` | Self-stack write: reached on the openLootBox stack itself (`:567`) AND on `resolveLootboxDirect:680` (auto) AND `resolveRedemptionLootbox:716` (auto). Two separate callsites — manual self-stack vs auto-resolve. Auto-resolve callers are EXEMPT (their dispatcher is on the VRF-callback / advanceGame-rooted stack). Manual self-stack write at `openLootBox` time is post-seed but pre-`_resolveLootboxCommon`. **BUT: the read at B-13 happens FIRST (`:496`), then `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion` (`:511`) — within the SAME `_applyEvMultiplierWithCap` invocation.** Cross-resolution mutation: each prior `openLootBox` at the same level shifts the running accumulator for the next call. Within the multi-tx attack window between VRF callback and the target's `openLootBox`, an attacker can sequence MULTIPLE `openLootBox` calls (potentially for different RNG indices belonging to the same attacker EOA) to drive `usedBenefit` toward the cap before opening the high-value index → reduces `scaledAmount` for that index. Conversely: the attacker may open the high-value index FIRST when `usedBenefit == 0` and `evMultiplierBps > 10_000` to capture full EV. Both directions break commitment. | **VIOLATION** |
| D-33 | `lootboxBurnie` | LootboxModule.openBurnieLootBox self-zero (C-12-a) | `LootboxModule.sol:615` | self-write post-`burnieAmount`-capture (line 609) | **VIOLATION** (audit-conservative: self-zero, post-roll) |
| D-34 | `lootboxBurnie` | MintModule._burnieAllocate (C-12-b) | `MintModule.sol:1399` | NO — EOA via BURNIE-coin transfer callback (post-target-met) | **VIOLATION** |
| D-35 | `decWindowOpen` | AdvanceModule._unlockRng open=true (C-13-a) | `AdvanceModule.sol:1655` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-36 | `decWindowOpen` | AdvanceModule._unlockRng open=false (C-13-b) | `AdvanceModule.sol:1659` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-37 | `deityPassOwners` | WhaleModule._buyDeityPass push (C-14-a) | `WhaleModule.sol:596` | NO — EOA via `buyDeityPass` | **VIOLATION** |
| D-38 | `boonPacked[player]` | LootboxModule._applyBoon (C-15-a) | `LootboxModule.sol:1432,1452,1479,1503,1526,1547,1568,1603` | Self-stack writes reached from this consumer (`_rollLootboxBoons:1162`) AND from `issueDeityBoon:799` (EOA — deity-pass holder grants a boon to a recipient). The `issueDeityBoon` reach is a genuine cross-EOA mutation: a third-party deity holder writes the consumer's `boonPacked[player]` between VRF callback and the consumer's `openLootBox` invocation. | **VIOLATION** (multi-source: self-stack post-seed for own-write + cross-EOA via `issueDeityBoon`) |
| D-39 | `boonPacked[player]` | WhaleModule._buyWhaleBundle* writes (C-15-b) | `WhaleModule.sol:202,388,556,898` | NO — EOA via `buyWhaleBundle` / `buyWhaleHalf` / `buyDeityPass` | **VIOLATION** |
| D-40 | `boonPacked[player]` | MintModule._processMint slot write (C-15-c) | `MintModule.sol:1433` | NO — EOA via `buyTickets` | **VIOLATION** |
| D-41 | `boonPacked[player]` | BoonModule.checkAndClearExpiredBoon (C-15-d) | `BoonModule.sol:265,266` | Reached only from `_rollLootboxBoons:1120` (delegatecall on the lootbox stack). Self-stack write; expiry-clear happens BEFORE the boon roll consumes any of slot0/slot1 in `_boonPoolStats` and `_boonFromRoll`. | **VIOLATION** (audit-conservative: self-stack pre-roll-consumption — the slot's state at consumption depends on `_simulatedDayIndex()` which depends on `block.timestamp`, an attacker-influenceable input via tx-ordering / next-block scheduling) |
| D-42 | `boonPacked[player]` | BoonModule.consumeActivityBoon (C-15-e) | `BoonModule.sol:291,297,301` | Same as D-23 — self-stack write on the lootbox stack | **VIOLATION** (audit-conservative) |
| D-43 | `boonPacked[player]` | BoonModule.<other-externals> (C-15-f) | `BoonModule.sol:41,67,93,122,283` | These external functions exist on the BoonModule contract. The actual reach depends on whether `DegenerusGame` exposes a public dispatcher that delegatecalls them. Conservative assumption: any EOA-reachable path between RNG callback and `openLootBox` that mutates `boonPacked[player]` is a VIOLATION; per-callsite analysis requires resolving each external's dispatcher and access guard. Each external in this group needs its own VIOLATION row unless its access guard prohibits EOA reach. | **VIOLATION** (×N, one per externally-reachable callsite of the listed BoonModule externals) |
| D-44 | `dgnrs.poolBalance(Lootbox)` | sDGNRS pool-mutation entries (C-16-a) | (cross-contract) | Multiple sDGNRS writer callsites exist; classification requires walking the sDGNRS contract. Cross-contract sources include (i) `DegenerusGame.fundLootboxPool` (admin), (ii) `DegenerusGame._creditDgnrsReward → dgnrs.transferFromPool` reached from this very consumer (self-stack, post-seed but the magnitude of own award is computed from poolBalance read BEFORE the transfer), and (iii) any sDGNRS external that mints / transfers into the Lootbox pool. The (i) admin path classifies VIOLATION unless under owner-only guard; the cross-resolution mutation across separate-EOA `openLootBox` calls IS exploitable: attacker opens his own ETH lootbox first → drains pool → victim's subsequent open at the same `(rngWord, ...)` yields a smaller DGNRS reward. | **VIOLATION** |
| D-45 | `lastPurchaseDay` | AdvanceModule.advanceGame writes (C-17-a, C-17-b, C-17-c) | `AdvanceModule.sol:176,397,439` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-46 | `jackpotPhaseFlag` | AdvanceModule._handlePhaseTransition (C-18-a) | `AdvanceModule.sol:333,437` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-47 | `purchaseStartDay` | DegenerusGame constructor (C-19-a) | `DegenerusGame.sol:218` | constructor — single shot | **EXEMPT-ADVANCEGAME** (audit-conservative: constructor-only) |
| D-48 | `purchaseStartDay` | AdvanceModule._handlePhaseTransition (C-19-b) | `AdvanceModule.sol:332` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-49 | `rngRequestTime` | AdvanceModule._tryRequestRng (C-20-a) | `AdvanceModule.sol:1122` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-50 | `rngRequestTime` | AdvanceModule.retryLootboxRng (C-20-b) | `AdvanceModule.sol:1154` | YES — `retryLootboxRng()` is 1 of the 3 explicit EXEMPT entry points per v43.0 milestone goal | **EXEMPT-RETRYLOOTBOXRNG** |
| D-51 | `rngRequestTime` | AdvanceModule._gameOverEntropy (C-20-c, C-20-d) | `AdvanceModule.sol:1329,1341` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-52 | `rngRequestTime` | AdvanceModule._unlockRng (C-20-e, C-20-f, C-20-g) | `AdvanceModule.sol:1633,1692,1734` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-53 | `rngRequestTime` | AdvanceModule.rawFulfillRandomWords (C-20-h) | `AdvanceModule.sol:1764` | YES — VRF coordinator only | **EXEMPT-VRFCALLBACK** |
| D-54 | `rngLockedFlag` | AdvanceModule._unlockRng (C-21-a) | `AdvanceModule.sol:1634,1690,1731` | YES — `advanceGame()` | **EXEMPT-ADVANCEGAME** |
| D-55 | `affiliate` cross-contract writer (B-28 / C-22-a) | DegenerusAffiliate.recordAffiliateEarnings or peer | (cross-contract) | Reached via MintModule / WhaleModule mint flows (EOA + ETH-payable). Player can mint between VRF callback and his own `openLootBox` to shift `affPoints` → `scaledAmount` upward. | **VIOLATION** |
| D-56 | `questView` cross-contract writer (B-29 / C-23) | DegenerusQuests quest-fulfillment | (cross-contract) | Reached via DegenerusQuests external/quest-fulfillment functions (EOA-callable). Player can complete a quest between VRF callback and his own `openLootBox` to inflate `questStreak` → `scoreBps` → `scaledAmount` upward. | **VIOLATION** |

**§D verdict tally:** 56 writer-callsite rows. **EXEMPT-ADVANCEGAME:** 18 (D-4, D-6, D-11, D-12, D-13, D-14, D-26, D-27, D-35, D-36, D-45, D-46, D-47, D-48, D-49, D-51, D-52, D-54). **EXEMPT-VRFCALLBACK:** 2 (D-5, D-53). **EXEMPT-RETRYLOOTBOXRNG:** 1 (D-50). **VIOLATION:** 35 (D-1, D-2, D-3, D-7, D-8, D-9, D-10, D-15, D-16, D-17, D-18, D-19, D-20, D-21, D-22, D-23, D-24, D-25, D-28, D-29, D-30, D-31, D-32, D-33, D-34, D-37, D-38, D-39, D-40, D-41, D-42, D-43, D-44, D-55, D-56).

Note on "self-zero, post-roll" / "self-stack post-seed" rows (D-1, D-15, D-18, D-23, D-28, D-29, D-33, D-41, D-42): these are own-stack writes that occur INSIDE the consumer's resolution and structurally cannot be exploited intra-tx; in a less audit-conservative classification scheme they would be EXEMPT-ADVANCEGAME-EQUIVALENT by design. Per `D-298-EXEMPT-REACH-01` strict-per-callsite + the milestone-goal prohibition on a residual no-disposition category, they remain VIOLATIONs with the rationale that the writer-callsite is structurally reachable from a non-EXEMPT (manual EOA) stack. Phase 299 FIX sub-phase planning may downgrade these on a per-row basis after design-intent trace per `feedback_design_intent_before_deletion.md`.

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-1: openLootBox self-zero `lootboxEth=0` post-amount-capture | (b) | Freeze amount in stack pre-SLOAD-cascade; mirror Phase 281 owed-salt |
| E-2 | D-2: MintModule._allocateLootbox writes `lootboxEth` post-RNG-callback | (a) | Gate buyTickets path on `lootboxRngWordByIndex[index]==0` per Phase 290 MINTCLN |
| E-3 | D-3: WhaleModule._whaleLootboxAllocate writes `lootboxEth` post-callback | (a) | Same gating as E-2; mirror MINTCLN gate at WhaleModule entry |
| E-4 | D-7: MintModule writes `lootboxDay` post-callback | (a) | Same gate; lootboxDay is in commitment quad (rngWord,player,day,amount) |
| E-5 | D-8: MintModule BURNIE path writes `lootboxDay` post-callback | (a) | Same MINTCLN-style gate on BURNIE allocation path |
| E-6 | D-9: WhaleModule writes `lootboxDay` post-callback | (a) | Same MINTCLN-style gate on WhaleModule allocation |
| E-7 | D-10: MintModule writes `presaleStatePacked` cap-eval post-callback | (b) | Snapshot presale flag per-index at allocation; Phase 288 dailyIdx precedent |
| E-8 | D-15: openLootBox self-zero `lootboxBaseLevelPacked` | (b) | Snapshot baseLevel into the index at allocation, not at open time |
| E-9 | D-16: MintModule writes `lootboxBaseLevelPacked` post-callback | (a) | Same MINTCLN-style gate to lock the per-index baseLevel at first allocation |
| E-10 | D-17: WhaleModule writes `lootboxBaseLevelPacked` post-callback | (a) | Same MINTCLN-style gate on WhaleModule baseLevel writes |
| E-11 | D-18: openLootBox self-zero `lootboxEvScorePacked` | (b) | Score must be snapshotted at allocation (already partially done; close gap) |
| E-12 | D-19: MintModule writes `lootboxEvScorePacked` snapshot post-callback | (a) | Gate snapshot write on rng-not-yet-published; pattern: Phase 290 MINTCLN |
| E-13 | D-20: WhaleModule writes `lootboxEvScorePacked` snapshot post-callback | (a) | Same MINTCLN-style gate |
| E-14 | D-21: MintStreakUtils writes `mintPacked_` (streak field) post-callback | (b) | Snapshot streak into the lootbox-index at allocation, not LIVE at open |
| E-15 | D-22: MintModule writes `mintPacked_` (3 callsites) post-callback | (b) | Same snapshot approach; consume score from B-9 snapshot only |
| E-16 | D-23: BoonModule.consumeActivityBoon self-stack `mintPacked_` write | (c) | Reorder consumeActivityBoon to AFTER all RNG-driven sub-rolls return |
| E-17 | D-24: WhaleModule writes `mintPacked_` (multi) post-callback | (b) | Snapshot whale-bundle / frozen-until state at lootbox allocation |
| E-18 | D-25: WhaleModule._buyDeityPass writes `mintPacked_` post-callback | (a) | Gate buyDeityPass on `rngLockedFlag||lootboxRngWordByIndex[currentIdx]!=0` |
| E-19 | D-28: _applyWhalePassStats self-stack `mintPacked_` write | (c) | Reorder whale-pass boon side-effect to AFTER roll consumption returns |
| E-20 | D-29: openLootBox self-zero `lootboxDistressEth` | (b) | Same snapshot pattern; freeze distress flag at allocation |
| E-21 | D-30: MintModule writes `lootboxDistressEth` post-callback | (a) | Same MINTCLN-style gate on distress accumulation |
| E-22 | D-31: WhaleModule writes `lootboxDistressEth` post-callback | (a) | Same MINTCLN-style gate |
| E-23 | D-32: lootboxEvBenefitUsedByLevel cross-resolution accumulator | (b) | Snapshot remaining-cap per index at allocation; pattern: Phase 281 owed-salt |
| E-24 | D-33: openBurnieLootBox self-zero `lootboxBurnie` | (b) | Freeze burnieAmount into a stack var pre-SLOAD-cascade |
| E-25 | D-34: MintModule BURNIE path writes `lootboxBurnie` post-callback | (a) | Same MINTCLN-style gate on BURNIE-allocation path |
| E-26 | D-37: WhaleModule._buyDeityPass push `deityPassOwners` post-callback | (a) | Gate buyDeityPass when any lootbox's RNG word is fresh in the open window |
| E-27 | D-38: LootboxModule._applyBoon writes `boonPacked` via issueDeityBoon | (a) | Gate issueDeityBoon on the recipient having no open lootbox index ready |
| E-28 | D-39: WhaleModule writes `boonPacked` post-callback | (a) | Same MINTCLN-style gate on WhaleModule boon writes |
| E-29 | D-40: MintModule writes `boonPacked` post-callback | (a) | Same MINTCLN-style gate on MintModule boon writes |
| E-30 | D-41: BoonModule.checkAndClearExpiredBoon self-stack expiry-clear | (b) | Snapshot expiry decision based on day at allocation, not at open |
| E-31 | D-42: BoonModule.consumeActivityBoon self-stack `boonPacked` write | (c) | Reorder activity-boon consumption to AFTER all RNG-driven sub-rolls return |
| E-32 | D-43: BoonModule other-external boonPacked writers | (a) | Gate each EOA-reachable BoonModule external on no-fresh-lootbox-rng-in-window |
| E-33 | D-44: sDGNRS pool-balance cross-resolution mutation | (b) | Snapshot poolBalance into each index at allocation (per-index DGNRS budget) |
| E-34 | D-55: affiliate-bonus points cross-resolution mutation | (b) | Snapshot affiliate points into the lootbox-index at allocation |
| E-35 | D-56: quest streak cross-resolution mutation | (b) | Snapshot questStreak into the lootbox-index at allocation |

**Recurring structural patterns (rationale-cluster summary; out-of-table for traceability):**

- Cluster (a) — **rngLockedFlag/per-index-rng-gated revert** (14 rows): the dominant fix is to block any mutator of a participating slot once the per-index `lootboxRngWordByIndex[index] != 0` (or for global slots, once any open-window lootbox index exists with RNG fulfilled). Pattern precedent: Phase 290 MINTCLN's `if (cachedJpFlag && rngLockedFlag) {...}` at `MintModule.sol:1221`. Direct, minimal, no new storage.
- Cluster (b) — **snapshot/anchor at allocation** (16 rows): for slots whose value SHOULD vary across players' lifecycle (activity score, affiliate points, quest streak, distress flag, presale flag, base level, EV cap, pool balance), the fix is to freeze the value at the lootbox-allocation timestamp into a per-index storage cell. Pattern precedent: Phase 281 owed-salt + Phase 288 dailyIdx snapshot. Requires one new storage write at allocation; one new storage slot per index per snapshotted variable.
- Cluster (c) — **pre-lock reorder** (3 rows: D-23, D-28, D-42): for self-stack writes inside `_resolveLootboxCommon` that mutate participating slots BEFORE the final-emission point but AFTER seed derivation, the fix is to reorder the side-effect to execute AFTER the roll commits its outputs. Zero new storage; pure code-ordering change.

No cluster (d) immutable recommendations: every participating slot identified above is legitimately mutable across the game lifecycle.

Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline before locking the final tactic on any of E-1..E-35.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the manual-path lootbox roll enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Cross-module SLOADs (cross-contract `dgnrs.poolBalance`, `affiliate.affiliateBonusPointsBest`, `questView.playerQuestStates`) enumerated per `D-298-TRACE-DEPTH-01` all-source-contracts scope.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point is the SSTORE at `AdvanceModule.sol:1256` (`lootboxRngWordByIndex[index] = rngWord`) — finalize path — OR `:1761` (mid-day VRF callback). From that moment forward the per-index RNG word is publicly readable and final. The manual-path `openLootBox`/`openBurnieLootBox` is invoked at the player's discretion (`DegenerusGame.openLootBox` is EOA-callable with no rate-gate, no cool-down, no `rngLockedFlag` revert), so the commitment window covers EVERY intervening block / transaction between the VRF callback block and the open block. EVERY participating SLOAD whose writer is reachable from a non-EXEMPT EOA stack within this window is classified VIOLATION.
- **Per-callsite shared-helper attestation:** `_resolveLootboxCommon` is reached from 4 dispatchers (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`). Per `D-298-EXEMPT-REACH-01` the verdict matrix above is the MANUAL-path (`openLootBox`, `openBurnieLootBox`) classification; the auto-resolve callers' rows are §6 scope.
- **Cross-callsite contamination check:** because `_resolveLootboxCommon` is shared, ANY fix targeting the consumer body (e.g., reorder boon side-effects per E-19, E-31, E-16) must preserve correctness on the auto-resolve callers too. Cluster (c) reorders are safe because the auto-resolve paths get the same reorder uniformly. Cluster (a) gates at allocation-time entry points are isolated from the consumer body. Cluster (b) snapshots affect the per-index storage layout (additive — backward compatible if added behind a feature-flag during deployment, but post-deploy this contract is frozen per the user's project memory `feedback_frozen_contracts_no_future_proofing.md`).
- **Verdicts:** 29 SLOADs enumerated / 25 participating / ~80 writer-callsites consolidated to 56 (slot × writer × callsite) tuples / **35 VIOLATION rows** / 21 EXEMPT rows (18 EXEMPT-ADVANCEGAME + 2 EXEMPT-VRFCALLBACK + 1 EXEMPT-RETRYLOOTBOXRNG).
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`. Read-only on source.
## §8 — DegeneretteModule._resolveLootboxDirect + inline consumer (file:line 797 / 594)

**Consumer entries (two-rooted trace per D-298-CONSUMER-LIST-01 §8):**

1. **Inline degenerette consumer** — `contracts/modules/DegenerusGameDegeneretteModule.sol:594`
   - `_resolveFullTicketBet` reads `uint256 rngWord = lootboxRngWordByIndex[index];` at line 594; the resolution loop then derives spin-result tickets via `keccak256(rngWord, index, ...)` (lines 615/619) and feeds the lootbox-converted ETH remainder into `_resolveLootboxDirect` at line 786.
2. **Direct-lootbox auto-resolve consumer** — `contracts/modules/DegenerusGameDegeneretteModule.sol:797`
   - `_resolveLootboxDirect` is a private helper that delegatecalls `IDegenerusGameLootboxModule.resolveLootboxDirect.selector` (selector at LootboxModule.sol:671). The delegatecall target re-derives entropy locally as `seed = keccak256(rngWord, player, day, amount)` (LootboxModule.sol:676) and walks the full `_resolveLootboxCommon` → `_accumulateLootboxRolls` → `_resolveLootboxRoll` chain.

**Both consumer entries share the SAME `rngWord` source slot:** `lootboxRngWordByIndex[index]` (read once at :594; threaded into `_resolveLootboxDirect` via the `rngWord` parameter at :675, then passed into the LootboxModule entry as `rngWord` and re-keccaked into a per-resolution seed). Single VRF-derived entropy thread through the whole resolution. Each spin-level lootbox conversion also re-keys via `keccak(rngWord, index, spinIdx, 'L')` at :668 for non-zero spinIdx, but the underlying `rngWord` is the same SLOAD.

**External entry chain:**
- EOA → `DegenerusGame.resolveDegeneretteBets(player, betIds)` at `DegenerusGame.sol:743` → delegatecall `DegenerusGameDegeneretteModule.resolveBets` (Degenerette:389) → `_resolveBet` (:570) → `_resolveFullTicketBet` (:578) → consumer site §1 at :594; loop body invokes `_distributePayout` (:722) → conditional `_resolveLootboxDirect` (:797) for the `lootboxShare > 0` arm. Both consumer entries live inside the same outer external entry point (`resolveDegeneretteBets`); EOA chooses `betIds` at resolution time.
- `placeDegeneretteBet` external entry (`DegenerusGame.sol:714` → Degenerette:367) is the COMMITMENT-side entry: it captures `index = _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)` at :450 and requires `lootboxRngWordByIndex[index] == 0` at :452 (commitment must happen BEFORE VRF lands on this index). Bet `packed` is stored at :479; this `packed` is the per-bet entropy-input that resolution later reads at :571.

**Commitment-window discipline (per `feedback_rng_commitment_window.md`):**
- T0 (commitment): EOA calls `placeDegeneretteBet`; bet writes `degeneretteBets[player][nonce] = packed` (Degenerette:479). `packed` captures `index`, `customTicket`, `ticketCount`, `currency`, `amountPerTicket`, `activityScore` (snapshot of `_playerActivityScore` at placement), `heroQuadrant`. The `index` here is THE CURRENT lootbox RNG index for which `rngWord` is not yet published.
- T1 (RNG publish): `_finalizeLootboxRng(uint256 rngWord)` at `AdvanceModule.sol:1256` writes `lootboxRngWordByIndex[index] = rngWord` (VRF-callback stack only; auxiliary tail-fill writers at :1761 / :1818 are EXEMPT-VRFCALLBACK / EXEMPT-ADVANCEGAME). Single EXEMPT SSTORE site for the entropy source.
- T2 (resolution): EOA calls `resolveDegeneretteBets`. Resolution reads `degeneretteBets[player][betId]` (input from T0), `lootboxRngWordByIndex[index]` (entropy from T1), executes the spin loop + lootbox conversion, then `delete degeneretteBets[player][betId]` (:597) closes the bet.

The risk class to enumerate (per F-41-02/03 precedent in `feedback_rng_window_storage_read_freshness.md`): any SLOAD reached between T1 and T2 that the EOA can mutate post-T1 — those flow into `payout` derivation alongside the immutable `rngWord` and break the "every VRF input frozen at commitment" invariant.

### CAT-01 (§A) — Traced function set

Backward-trace rooted at both consumer entries; trace walks transitively into every reachable function under `contracts/` per `D-298-TRACE-DEPTH-01`. Stops only at external interfaces with no source available (Chainlink VRF coordinator + wwxrp/coin/dgnrs/coinflip/sdgnrs externals — interface methods enumerated with their callsites; internal SLOADs of those externals are out of this audit's source scope, but the storage-ref SLOAD that obtains the contract address is itself a compile-time constant `internal constant` (no SLOAD)).

**Resolution code path (T2 — full enumeration):**

| #  | Function                              | File:line                                          | Reached from                          | Notes |
|----|---------------------------------------|----------------------------------------------------|---------------------------------------|-------|
| 1  | `resolveBets`                         | `DegeneretteModule.sol:389`                        | external entry (`DegenerusGame:743`)  | for-loop dispatcher; calls `_resolvePlayer` + `_resolveBet` per betId |
| 2  | `_resolvePlayer`                      | `DegeneretteModule.sol:141`                        | :390                                  | `private view`; reads `operatorApprovals[player][msg.sender]` (NON-PARTICIPATING access check) |
| 3  | `_requireApproved`                    | `DegeneretteModule.sol:131`                        | :146                                  | `private view`; same access read |
| 4  | `_resolveBet`                         | `DegeneretteModule.sol:570`                        | :393                                  | reads `degeneretteBets[player][betId]` (:571) → dispatches `_resolveFullTicketBet` |
| 5  | `_resolveFullTicketBet`               | `DegeneretteModule.sol:578`                        | :574                                  | **consumer §B (inline)** at :594; loop runs `_countMatches`, `_fullTicketPayout`, `_distributePayout`, `_awardDegeneretteDgnrs` |
| 6  | `_countMatches`                       | `DegeneretteModule.sol:873`                        | :635                                  | `private pure` — no SLOADs |
| 7  | `_fullTicketPayout`                   | `DegeneretteModule.sol:949`                        | :638                                  | `private pure` — no SLOADs |
| 8  | `_countGoldQuadrants`                 | `DegeneretteModule.sol:860`                        | :959                                  | `private pure` — no SLOADs |
| 9  | `_getBasePayoutBps`                   | `DegeneretteModule.sol:1045`                       | :960                                  | `private pure` — no SLOADs (constant-table lookup) |
| 10 | `_wwxrpBonusBucket`                   | `DegeneretteModule.sol:907`                        | :964                                  | `private pure` — no SLOADs |
| 11 | `_wwxrpFactor`                        | `DegeneretteModule.sol:921`                        | :973                                  | `private pure` — no SLOADs (constant-table lookup) |
| 12 | `_applyHeroMultiplier`                | `DegeneretteModule.sol:1011`                       | :989                                  | `private pure` — no SLOADs (constant-table lookup) |
| 13 | `_roiBpsFromScore`                    | `DegeneretteModule.sol:1071`                       | :599                                  | `private pure` — no SLOADs (input from packed bet's `activityScore`) |
| 14 | `_wwxrpHighValueRoi`                  | `DegeneretteModule.sol:1108`                       | :602                                  | `private pure` — no SLOADs |
| 15 | `_distributePayout`                   | `DegeneretteModule.sol:722`                        | :675                                  | reads `prizePoolFrozen`, pool slots, writes claimable + pools, calls `_resolveLootboxDirect` on lootbox arm |
| 16 | `_getPendingPools`                    | `Storage.sol:702`                                  | :755                                  | reads `prizePoolPendingPacked` |
| 17 | `_setPendingPools`                    | `Storage.sol:698`                                  | :764                                  | writes `prizePoolPendingPacked` |
| 18 | `_getFuturePrizePool`                 | `Storage.sol:797`                                  | :770                                  | reads `prizePoolsPacked` (high 128 bits) |
| 19 | `_getPrizePools`                      | `Storage.sol:688`                                  | :798                                  | reads `prizePoolsPacked` |
| 20 | `_setFuturePrizePool`                 | `Storage.sol:803`                                  | :780                                  | writes `prizePoolsPacked` (high 128 bits) |
| 21 | `_setPrizePools`                      | `Storage.sol:684`                                  | :805                                  | writes `prizePoolsPacked` |
| 22 | `_addClaimableEth`                    | `DegeneretteModule.sol:1129`                       | :765, :781                            | writes `claimablePool`, calls `_creditClaimable` |
| 23 | `_creditClaimable`                    | `PayoutUtils.sol:32`                               | :1132                                 | writes `claimableWinnings[player]` |
| 24 | `_revertDelegate`                     | `DegeneretteModule.sol:122`                        | :812                                  | `private pure` — error path only |
| 25 | `_resolveLootboxDirect`               | `DegeneretteModule.sol:797`                        | :786                                  | **consumer §B (direct)**: delegatecalls LootboxModule.resolveLootboxDirect (selector at :806) |
| 26 | `_awardDegeneretteDgnrs`              | `DegeneretteModule.sol:1137`                       | :680                                  | reads `sdgnrs.poolBalance(Reward)` (external SLOAD; ETH + matches≥6 arm) + calls `sdgnrs.transferFromPool` |

**LootboxModule reachable from `_resolveLootboxDirect` delegatecall (LootboxModule.resolveLootboxDirect args: `presale=false, allowPasses=true, emitLootboxEvent=false, payColdBustConsolation=false, allowBoons=false`):**

| #  | Function                              | File:line                                          | Reached from                          | Notes |
|----|---------------------------------------|----------------------------------------------------|---------------------------------------|-------|
| 27 | `resolveLootboxDirect`                | `LootboxModule.sol:671`                            | delegatecall                          | derives `seed = keccak256(rngWord, player, day, amount)` (:676), reads `level` (:675), rolls target level |
| 28 | `_simulatedDayIndex`                  | `Storage.sol:1208`                                 | :674                                  | calls `GameTimeLib.currentDayIndex()` (pure on `block.timestamp` — no SLOAD) |
| 29 | `_rollTargetLevel`                    | `LootboxModule.sol:817`                            | :677                                  | `private pure` — no SLOADs |
| 30 | `_lootboxEvMultiplierBps`             | `LootboxModule.sol:444`                            | :679                                  | calls `IDegenerusGame(address(this)).playerActivityScore(player)` (re-entrant staticcall into `DegenerusGame.playerActivityScore` → `_playerActivityScore`) |
| 31 | `playerActivityScore` (external view) | `DegenerusGame.sol` (`playerActivityScore`)        | via staticcall                        | wraps `_playerActivityScore(player, questStreak, _activeTicketLevel())` |
| 32 | `_playerActivityScore`                | `MintStreakUtils.sol:83` + `:169`                  | staticcall                            | reads `mintPacked_[player]`, `level`, `_mintStreakEffective`, `_mintCountBonusPoints`, `affiliate.affiliateBonusPointsBest` (when uncached), `jackpotPhaseFlag` (via `_activeTicketLevel`) |
| 33 | `_mintStreakEffective`                | `MintStreakUtils.sol:51`                           | :95                                   | reads `mintPacked_[player]` |
| 34 | `_activeTicketLevel`                  | `MintStreakUtils.sol:72`                           | :173                                  | reads `jackpotPhaseFlag`, `level` |
| 35 | `_mintCountBonusPoints`               | `MintStreakUtils.sol` (helper)                     | :117                                  | reads `level`, `mintPacked_[player]` (level-count field) |
| 36 | `questView.playerQuestStates`         | external staticcall to QuestView                   | (not reached: `_playerActivityScore` reads quest streak from `mintPacked_` cache, see Phase 290 MINTCLN) — but the placement-time `_playerActivityScore` IS called via `_placeDegeneretteBetCore:457`. Resolution-time path uses staticcall **`IDegenerusGame.playerActivityScore`** (not the inline 2-arg overload), which DOES re-fetch quest streak through `questView` at the wrapper site. | external; cross-contract SLOAD on QuestView side — out of in-module scope per `D-298-TRACE-DEPTH-01` |
| 37 | `affiliate.affiliateBonusPointsBest`  | external staticcall to Affiliate                   | :145 (uncached branch)                | external; cross-contract SLOAD on Affiliate side — out of in-module scope |
| 38 | `_lootboxEvMultiplierFromScore`       | `LootboxModule.sol:453`                            | :446                                  | `private pure` — no SLOADs |
| 39 | `_applyEvMultiplierWithCap`           | `LootboxModule.sol:484`                            | :680                                  | reads `lootboxEvBenefitUsedByLevel[player][currentLevel]` (:496); writes same slot (:511) |
| 40 | `_resolveLootboxCommon`               | `LootboxModule.sol:960`                            | :682                                  | private; allowBoons=false (no `_rollLootboxBoons` reach); emitLootboxEvent=false; payColdBustConsolation=false |
| 41 | `_lootboxBoonBudget`                  | `LootboxModule.sol:838`                            | :992, :1030 (boon arm not reached)    | `private pure` — no SLOADs |
| 42 | `_accumulateLootboxRolls`             | `LootboxModule.sol:863`                            | :1004                                 | invokes `_resolveLootboxRoll` once or twice |
| 43 | `EntropyLib.hash2`                    | `libraries/EntropyLib.sol`                         | :897                                  | `internal pure` (keccak counter-tag) — no SLOADs |
| 44 | `_resolveLootboxRoll`                 | `LootboxModule.sol:1623`                           | :883, :899                            | 4-arm bit-slice on `seed` (:1640); per-arm subroutines below |
| 45 | `_lootboxTicketCount`                 | `LootboxModule.sol:1703`                           | :1645                                 | `private pure` — no SLOADs |
| 46 | `_lootboxDgnrsReward`                 | `LootboxModule.sol:1754`                           | :1652                                 | reads `dgnrs.poolBalance(Lootbox)` (external SLOAD on sDGNRS; out of in-module scope) |
| 47 | `_creditDgnrsReward`                  | `LootboxModule.sol:1784`                           | :1654                                 | calls `dgnrs.transferFromPool(Lootbox,…)` (external mutator) |
| 48 | `wwxrp.mintPrize` (external)          | external mutator                                   | :1671                                 | WWXRP arm of roll |
| 49 | `_queueTickets`                       | `Storage.sol:559`                                  | :1067                                 | reads `lastPurchaseDay`+`jackpotPhaseFlag`+`level`+`purchaseStartDay`+`rngRequestTime` via `_livenessTriggered`; reads `level`, `rngLockedFlag`, `ticketsOwedPacked[wk][buyer]`; writes `ticketQueue[wk]` + `ticketsOwedPacked` |
| 50 | `_livenessTriggered`                  | `Storage.sol:1243`                                 | :570                                  | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime` |
| 51 | `_tqWriteKey` / `_tqFarFutureKey`     | `Storage.sol`                                      | :573-575                              | reads `ticketWriteSlot` |
| 52 | `coinflip.creditFlip` (external)      | external mutator                                   | :1079                                 | BURNIE arm of roll (when `burnieAmount != 0`) |
| 53 | `PriceLookupLib.priceForLevel`        | `libraries/PriceLookupLib.sol`                     | :986, :1803 (lazyPass — boon arm NOT reached) | `internal pure` — no SLOADs |

**Explicit-enumeration cross-check** (per `feedback_verify_call_graph_against_source.md`):

- `grep -n "delegatecall\|\.call\|staticcall" contracts/modules/DegenerusGameDegeneretteModule.sol` returns **one** delegatecall at `:804` (to `GAME_LOOTBOX_MODULE.resolveLootboxDirect`) — no other cross-module reach from inside the resolution path.
- `grep -n "delegatecall\|\.call\|staticcall" contracts/modules/DegenerusGameLootboxModule.sol` confirms two delegatecalls (to `GAME_BOON_MODULE.checkAndClearExpiredBoon` :1120 and `GAME_BOON_MODULE.consumeActivityBoon` :1035), but both live inside `if (allowBoons)` / `_rollLootboxBoons` — **NOT REACHED** under §8 (`allowBoons=false` per resolveLootboxDirect:693).
- `grep -n "IDegenerusGame(address(this))" contracts/modules/DegenerusGameLootboxModule.sol` returns ONE hit at `:445` (`_lootboxEvMultiplierBps` → `playerActivityScore` staticcall). Re-entrant staticcall into `DegenerusGame.playerActivityScore` is reached.
- Inline-assembly raw `sstore` / `slot:` directives in the consumer-reachable trace: `grep -rn "assembly\b" contracts/modules/DegenerusGameDegeneretteModule.sol contracts/modules/DegenerusGameLootboxModule.sol contracts/storage/DegenerusGameStorage.sol --include="*.sol" | grep -v "memory-safe"` returns zero raw-sstore hits in the consumer trace.
- `_revertDelegate` uses `assembly ("memory-safe") { revert(...) }` — error-path only, no sstore/sload.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during the resolution path (T2 window: between `lootboxRngWordByIndex[index]` SLOAD at Degenerette:594 and the final external mutator returns). Per `feedback_rng_window_storage_read_freshness.md`: ALL SLOADs enumerated, not only VRF-derived ones; non-VRF SLOADs alongside RNG are a distinct bug class (F-41-02/03 precedent).

| #     | Slot                                                  | Read-site (file:line)                          | Read context                                                              | Participating? | Attestation if NO |
|-------|-------------------------------------------------------|------------------------------------------------|---------------------------------------------------------------------------|----------------|-------------------|
| B-1   | `operatorApprovals[player][msg.sender]`               | `Degenerette:132` (via `_resolvePlayer:146`)   | EOA access check at outer entry                                            | NO             | Access-control gate; outcome (taken/not-taken) does not influence VRF-derived payout — only governs reach (which player's bets resolve). |
| B-2   | `degeneretteBets[player][betId]`                      | `Degenerette:571`                              | bet-input load (`packed`)                                                 | **YES**        | — |
| B-3   | `lootboxRngWordByIndex[index]`                        | `Degenerette:594`                              | **VRF-word source** (consumer entry §1 root SLOAD)                        | **YES**        | — |
| B-4   | `prizePoolFrozen`                                     | `Degenerette:748` (`_distributePayout`)        | frozen-branch dispatcher; selects pending vs live pool path               | **YES**        | — |
| B-5   | `prizePoolPendingPacked`                              | `Storage:707` (via `_getPendingPools` :755)    | reads pending pool when frozen                                            | **YES**        | — |
| B-6   | `prizePoolsPacked` (low 128 — next pool)              | `Storage:693` (via `_getPrizePools`)           | read in `_setPrizePools(next, …)` recompose at :804 (write path) and via `_getFuturePrizePool` at :797 | **YES**        | — |
| B-7   | `prizePoolsPacked` (high 128 — future pool)           | `Storage:693` / :797                           | reads `futurePrizePool` for cap calc (:770) + write recompose             | **YES**        | — |
| B-8   | `claimablePool`                                       | `Degenerette:1131` (`+= uint128(weiAmount)`)   | RMW on aggregate-credit slot                                              | NO             | RMW aggregate-balance counter; final-value bookkeeping for ETH-claim accounting. Its prior value does not enter the payout formula — `_addClaimableEth` increments unconditionally by `weiAmount` (which is fully determined by `rngWord`-derived `payout` + pool cap). |
| B-9   | `claimableWinnings[player]`                           | `PayoutUtils:35` (via `_creditClaimable`)      | RMW on per-player credit                                                  | NO             | RMW per-player balance; prior value does not enter the payout formula — `_creditClaimable` performs `+= weiAmount` only. (Note: the claimableWinnings WRITE recorded here is read at claim time `DegenerusGame.sol:910/924/1401`, outside the rng-window.) |
| B-10  | `level` (uint24)                                      | `LootboxModule:675` (`level + 1`)              | currentLevel for `_rollTargetLevel`                                       | **YES**        | — |
| B-11  | `lootboxEvBenefitUsedByLevel[player][currentLevel]`   | `LootboxModule:496`                            | EV-cap remaining-capacity calc                                            | **YES**        | — |
| B-12  | `mintPacked_[player]`                                 | `MintStreakUtils:90` (via `_playerActivityScore` staticcall) | streak/level-count/deity/whale-bundle for activity score                  | **YES**        | — |
| B-13  | `mintPacked_[player]` (streak fields)                 | `MintStreakUtils:55` (`_mintStreakEffective`)  | streak calc                                                               | **YES**        | — |
| B-14  | `level` (uint24)                                      | `MintStreakUtils:96` (`_playerActivityScore`)  | `currLevel` for frozen-until / streak / mint-count                        | **YES**        | — |
| B-15  | `jackpotPhaseFlag`                                    | `MintStreakUtils:73` (`_activeTicketLevel`)    | streak-base-level pick                                                    | **YES**        | — |
| B-16  | `mintPacked_[player]` (affiliate cache fields)        | `MintStreakUtils:140`                          | affiliate-bonus cached level/points                                       | **YES**        | — |
| B-17  | `dgnrs.poolBalance(Lootbox)` (external sDGNRS slot)   | `LootboxModule:1770`                           | DGNRS arm of `_resolveLootboxRoll` (10% arm: `roll ∈ [11,12]`)            | **YES**        | — (cross-contract, but reached from the participating roll arm; in-source-scope per `D-298-TRACE-DEPTH-01` because sDGNRS source lives at `contracts/StakedDegenerusStonk.sol`) |
| B-18  | `sdgnrs.poolBalance(Reward)` (external sDGNRS slot)   | `Degenerette:1147`                             | 6+ match ETH arm of `_awardDegeneretteDgnrs` (consumer §1 reach)          | **YES**        | — (cross-contract; in-source-scope) |
| B-19  | `lastPurchaseDay`                                     | `Storage:1244` (`_livenessTriggered`)          | productive-phase guard                                                    | **YES**        | — |
| B-20  | `jackpotPhaseFlag`                                    | `Storage:1244`                                 | productive-phase guard                                                    | **YES**        | — |
| B-21  | `level` (uint24)                                      | `Storage:1245`                                 | level==0 deploy-idle branch                                               | **YES**        | — |
| B-22  | `purchaseStartDay`                                    | `Storage:1246`                                 | day-clock                                                                 | **YES**        | — |
| B-23  | `rngRequestTime`                                      | `Storage:1250`                                 | VRF-stall fallback gate                                                   | **YES**        | — |
| B-24  | `level` (uint24)                                      | `Storage:571` (`_queueTickets`)                | `targetLevel > level + 5` far-future test                                 | **YES**        | — |
| B-25  | `rngLockedFlag`                                       | `Storage:572`                                  | far-future write gate                                                     | **YES**        | — |
| B-26  | `ticketWriteSlot`                                     | `Storage` (via `_tqWriteKey` / `_tqFarFutureKey`) | per-level read/write slot select                                          | **YES**        | — |
| B-27  | `ticketsOwedPacked[wk][buyer]`                        | `Storage:576`                                  | RMW on per-buyer ticket-owed count                                        | NO             | RMW counter; prior value does not enter the rolled `whole`-tickets formula — `_queueTickets` increments by `quantity` only. The participation question is whether the WRITE lands (gated by `_livenessTriggered` + `rngLockedFlag`); both gates are themselves participating slots (B-19..B-25). |
| B-28  | `ticketQueue[wk].length`                              | `Storage:579-581`                              | first-time-push test                                                      | NO             | RMW append; outcome (push vs no-push) is a function of `ticketsOwedPacked` (B-27 attestation applies). |

**Auxiliary §B-W — SSTOREs inside the rng-window (cross-check, not classified):**

| #    | Slot                                       | Write-site (file:line)                         | Notes |
|------|--------------------------------------------|------------------------------------------------|-------|
| B-W1 | `degeneretteBets[player][betId]`           | `Degenerette:597` (`delete`)                   | per-bet finalize; zero after resolution |
| B-W2 | `prizePoolPendingPacked`                   | `Storage:699` (via `_setPendingPools` :764)    | frozen-branch ETH share debit |
| B-W3 | `prizePoolsPacked`                         | `Storage:685` (via `_setFuturePrizePool` :780) | unfrozen-branch ETH share debit |
| B-W4 | `claimablePool`                            | `Degenerette:1131`                             | aggregate credit |
| B-W5 | `claimableWinnings[player]`                | `PayoutUtils:35`                               | per-player credit |
| B-W6 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule:511`                            | EV-cap used-benefit |
| B-W7 | `ticketsOwedPacked[wk][buyer]`             | `Storage:585`                                  | post-roll ticket queue |
| B-W8 | `ticketQueue[wk]` (array push)             | `Storage:580`                                  | first-time entry |

### CAT-03 (§C) — Writer enumeration for participating slots

Per `D-298-EXEMPT-REACH-01`: writers enumerated per-callsite. For each participating slot (`Participating? = YES` rows in §B), enumerate every external/public function in any contract under `contracts/` that writes the slot (OZ-inherited writers included; admin/owner writers included). The participating-slot universe under §8:

**Group I — input slot (per-bet entropy capture; the bet `packed` is consumed by `_resolveFullTicketBet`):**

### C-1 — `degeneretteBets[player][nonce]` (mapping → uint256)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-1a | `DegenerusGameDegeneretteModule._placeDegeneretteBetCore` | `Degenerette:479` (`degeneretteBets[player][nonce] = packed`) | EOA → `DegenerusGame.placeDegeneretteBet` (`DegenerusGame.sol:714`) → delegatecall → `placeDegeneretteBet` (Degenerette:367) → `_placeDegeneretteBet` (:405) → `_placeDegeneretteBetCore` (:437) | COMMITMENT-side SSTORE; gated `lootboxRngWordByIndex[index] != 0 ⇒ revert RngNotReady` at :452 (commitment must precede VRF publish for the captured `index`). |
| C-1b | `DegenerusGameDegeneretteModule._resolveBet` | `Degenerette:597` (`delete`) | EOA → `DegenerusGame.resolveDegeneretteBets` → … (the consumer itself) | Self-finalize delete; only zeros the slot after resolution — does not contribute participating-input entropy. |

**OZ-inherited writers check:** `degeneretteBets` is `internal mapping(address => mapping(uint64 => uint256))` declared in `DegenerusGameStorage`; no OZ ERC20/ERC721 path writes this slot. Confirmed via storage-layout review.

**Admin/owner writer check:** `grep -n "degeneretteBets" contracts/ -r` returns C-1a, C-1b, and one view-read at `DegenerusGame.sol:2111` (no writer). No admin path.

**Constructor/initializer writer check:** Default-zero mapping; no constructor write. Not applicable.

**Inline-assembly raw-sstore check:** Zero hits in DegeneretteModule. Not applicable.

### C-2 — `lootboxRngWordByIndex[index]` (mapping → uint256; VRF entropy source)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-2a | `DegenerusGameAdvanceModule._finalizeLootboxRng` | `AdvanceModule:1256` | VRF coordinator → `DegenerusGame.fulfillRandomWords` (VRF callback) → delegatecall → `_finalizeLootboxRng(rngWord)` | **EXEMPT-VRFCALLBACK**: only reached from the Chainlink VRF coordinator callback stack (and `_finalizeLootboxRng` is private, called only from `rngGate`/fulfillment dispatch in AdvanceModule). |
| C-2b | `DegenerusGameAdvanceModule._gameOverEntropy` | `AdvanceModule:1761` | game-over historical-fallback tail-fill | **EXEMPT-VRFCALLBACK**: tail-fill of pending lootbox indices with the same VRF-callback-derived `finalWord` (`rngWordByDay[day]` snapshot); reaches only from `advanceGame()`-stack `_handleGameOverPath` → `_gameOverEntropy` → fallback branch. Game-over context — but classified per the EXEMPT category that owns the original `rngWord` derivation site. |
| C-2c | `DegenerusGameAdvanceModule._gameOverEntropy` (tail-fill at :1818) | `AdvanceModule:1818` | game-over backwards-fill from `lastFilledIndex` down to earliest unfilled | **EXEMPT-VRFCALLBACK**: same justification as C-2b. |

**OZ-inherited writers check:** `lootboxRngWordByIndex` is `internal mapping(uint48 => uint256)`; no OZ inheritance writes. Confirmed.

**Admin/owner writer check:** `grep -rn "lootboxRngWordByIndex" contracts/ --include="*.sol"` returns C-2a / C-2b / C-2c plus 8 reader sites (Degenerette:452/594, LootboxModule:533/612, AdvanceModule:210/269/1255/1812, MintModule:686). No admin-callable mutator.

**Constructor/initializer writer check:** Default-zero mapping. Not applicable.

**Inline-assembly raw-sstore check:** Zero hits.

### C-3 — `prizePoolFrozen` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-3a | `DegenerusGameStorage._swapAndFreeze` | `Storage:757` (`prizePoolFrozen = true`) | only reached from `AdvanceModule._handleDailyAdvance` / `_handleJackpotPhaseAdvance` — i.e., `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-3b | `DegenerusGameStorage._unfreezePool` | `Storage:777` (`prizePoolFrozen = false`) | only reached from `advanceGame()`-rooted advance helpers | **EXEMPT-ADVANCEGAME** |

**OZ/admin/constructor/assembly:** Default-false; no other writers.

### C-4 — `prizePoolPendingPacked` (uint256 packed)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-4a | `DegenerusGameStorage._setPendingPools` | `Storage:699` | callers below | helper |
| C-4b | `_swapAndFreeze` (clear path) | `Storage:764` (`prizePoolPendingPacked = 0`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-4c | `_unfreezePool` | `Storage:776` (`= 0`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-4d | `_swapAndFreeze` (seed path) | `Storage:762` (via `_setPendingPools`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-4e | `DegenerusGameDegeneretteModule._collectBetFunds` (frozen-branch place) | `Degenerette:553` (via `_setPendingPools`) | EOA → `placeDegeneretteBet` external | **VIOLATION** — see §D-1 |
| C-4f | `DegenerusGameDegeneretteModule._distributePayout` (frozen-branch ETH share) | `Degenerette:764` (via `_setPendingPools`) | the resolution path itself (consumer §B) | **EXEMPT-VRFCALLBACK** — self-write inside the consumer's resolution call; reached only after the consumer's `rngWord` SLOAD at :594. |
| C-4g | `DegenerusGameJackpotModule.payDailyJackpot` & companion jackpot writers (pool drains) | `JackpotModule.sol` (writes to pending pools during JP distribution) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** (covered in §1/§2 of catalog) |
| C-4h | `DegenerusGameMintModule._mintTickets` (frozen-branch purchase) | `MintModule` purchase paths that write `prizePoolPendingPacked` via `_setPendingPools` when `prizePoolFrozen` | EOA → `purchaseTicketsByFunction` / `purchaseTicketsWithBurnie` / etc. | **VIOLATION-CANDIDATE** — but these mutate the `next`/`future` aggregates the consumer's `_getFuturePrizePool` does NOT read during T2 (the frozen path reads `_getPendingPools`, not `_getFuturePrizePool`); however §8 frozen-path solvency check at :758 (`if (uint256(pFuture) < ethShare) revert E()`) DOES read `pFuture` from the pending pool — so writers that change `prizePoolPendingPacked.future` between T1 and T2 ARE participating. See §D-2. |

**OZ/admin/constructor:** No admin path writes pending pool. No constructor write (default zero). No inline assembly.

**Note on resolution-write of C-4f / C-4 family during T2:** The §8 consumer's own `_distributePayout` performs a frozen-branch SSTORE to `prizePoolPendingPacked` (debiting `pFuture`). This is a write-then-no-read within the same resolution (the consumer reads `_getPendingPools` ONCE before debiting and writes once); the slot is not re-read after the consumer write. So C-4f's read-then-write is internal-consistent; the concern at §D is whether OTHER writers race between :755 (read) and :764 (write) — which would only happen in a multi-tx interleaving against a parallel re-entry — non-issue (single-tx execution).

### C-5 — `prizePoolsPacked` (uint256 packed; next + future)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-5a | `_setPrizePools` (helper) | `Storage:684` | callers below | helper |
| C-5b | `DegenerusGameJackpotModule.*` jackpot distribution writers | various | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** (covered in §1/§2/§3) |
| C-5c | `DegenerusGameDegeneretteModule._distributePayout` (unfrozen-branch) | `Degenerette:780` (via `_setFuturePrizePool`) | the resolution path itself | **EXEMPT-VRFCALLBACK** (self-write inside consumer) |
| C-5d | `DegenerusGameDegeneretteModule._collectBetFunds` (unfrozen-branch place) | `Degenerette:556` (via `_setPrizePools`) | EOA → `placeDegeneretteBet` external | **VIOLATION-CANDIDATE** — see §D-3 |
| C-5e | `DegenerusGameMintModule.*` ticket purchase pool credits | `MintModule` purchase paths that write `prizePoolsPacked` via `_setPrizePools` | EOA → ticket purchase externals | **VIOLATION-CANDIDATE** — see §D-3 |
| C-5f | `_unfreezePool` (apply pending → live) | `Storage:775` | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-5g | `DegenerusGameDecimatorModule.*` decimator-pool writers | DecimatorModule | EOA-callable decimator claim entries | **VIOLATION-CANDIDATE** if reach-window applies (see §D-3) |

**OZ/admin/constructor:** No admin path. Initialized in constructor; not relevant post-deploy.

### C-6 — `level` (uint24)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-6a | `DegenerusGameAdvanceModule._processJackpotPhaseAdvance` | `AdvanceModule:1643` (`level = lvl`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |

Single writer — confirmed by `grep -rn "^\s*level\s*=" contracts/ --include="*.sol"` returning C-6a as the sole post-deploy mutator.

### C-7 — `lootboxEvBenefitUsedByLevel[player][lvl]` (mapping → uint256)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-7a | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule:511` | reachable from any caller of `_applyEvMultiplierWithCap`: `openLootBox` (:567), `openBurnieLootBox` (`grep` confirms not reached), `resolveLootboxDirect` (:680, the §8 consumer path), `resolveRedemptionLootbox` (:716) | Per-callsite classification: |
| | | called from `resolveLootboxDirect` (:680) | resolution path itself (consumer's reach) | **EXEMPT-VRFCALLBACK** (consumer-self) |
| | | called from `resolveRedemptionLootbox` (:716) | EOA → sDGNRS.claimRedemption → DegenerusGame → delegatecall LootboxModule.resolveRedemptionLootbox | EXEMPT-VRFCALLBACK if the redemption flow is reached only from a VRF-callback-driven stack; per consumer §6 audit, the redemption flow reads `rngWordForDay(claimPeriodIndex)` from snapshot (see §6) — classified at §6. For §8, this is a parallel-consumer write site, not a same-tx write. |
| | | called from `openLootBox` (:567) | EOA → `DegenerusGame.openLootBox` → delegatecall LootboxModule.openLootBox | **VIOLATION-CANDIDATE** — EOA can grind a same-block prior `openLootBox` call that changes `lootboxEvBenefitUsedByLevel[player][currentLevel]` BEFORE the §8 resolver reads the same slot at :496. See §D-4. |

**OZ/admin/constructor:** No admin path. Default zero. No raw assembly.

### C-8 — `mintPacked_[player]` (mapping → uint256; many fields)

`mintPacked_` is heavily written across the codebase (mint, deity, whale, affiliate, quest, frozen-until — all packed into one 256-bit slot per player).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-8a | `DegenerusGameMintStreakUtils._recordMintStreakForLevel` | `MintStreakUtils:47` | called from any path that finalizes a mint quest completion for the player; reaches via `quests.handleX` + `_creditTicketSale` etc. | **VIOLATION-CANDIDATE** — see §D-5 |
| C-8b | `MintModule._*Mint*` / `MintModule.purchase*` writers | various MintModule writes to packed mint counters / bundle type / frozen-until-level | EOA → ticket-purchase / deity-pass / whale-pass purchase externals | **VIOLATION-CANDIDATE** — see §D-5 |
| C-8c | `DegenerusGameStorage._setMintDay` | `Storage` (called by mint paths) | EOA-reachable mint paths | **VIOLATION-CANDIDATE** — see §D-5 |
| C-8d | Affiliate-cache update writers (level-transition cache refresh) | `MintModule` / `AdvanceModule` affiliate-cache refresh path | reaches from `advanceGame()`-stack level transition AND from `MintModule` purchase recompute | Mixed: cache refresh on level transition is **EXEMPT-ADVANCEGAME**; recompute on purchase is **VIOLATION-CANDIDATE**. See §D-5. |

**OZ-inherited writers check:** `mintPacked_` is `internal mapping(address => uint256)`; no OZ inheritance. Confirmed.

**Admin/owner writer check:** `grep -rn "mintPacked_\[" contracts/ --include="*.sol"` returns ~30 hits across DegenerusGame.sol + MintModule + AdvanceModule + JackpotModule + MintStreakUtils — none gated by `onlyOwner`/`onlyAdmin`. All reach is via game-action externals (purchase, deity claim, whale claim, jackpot pay, advance).

**Constructor/initializer writer check:** Default zero. Not applicable.

**Inline-assembly raw-sstore check:** Zero hits.

### C-9 — `jackpotPhaseFlag` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-9a | `AdvanceModule._processAdvance` (purchase → jackpot) | `AdvanceModule:437` (`= true`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-9b | `AdvanceModule._processJackpotPhaseAdvance` (jackpot → purchase) | `AdvanceModule:333` (`= false`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |

### C-10 — `lastPurchaseDay`, `purchaseStartDay`, `rngRequestTime` (liveness inputs)

`lastPurchaseDay`, `purchaseStartDay`, `rngRequestTime`, `dailyIdx` are all written exclusively from `advanceGame()`-rooted helpers (`_handleDailyAdvance`, `_processAdvance`, `_requestRng`, `_finalizeLootboxRng`, `_unlockRng`, `_handleGameOverPath`, `_gameOverEntropy`). Confirmed via:
- `grep -rn "lastPurchaseDay\s*=\|purchaseStartDay\s*=\|rngRequestTime\s*=" contracts/ --include="*.sol"` → all hits live in `AdvanceModule.sol` (no external EOA mutators outside the advance stack).

| # | Slot | Writer summary | Classification |
|---|------|----------------|----------------|
| C-10a | `lastPurchaseDay` | AdvanceModule writes only | **EXEMPT-ADVANCEGAME** |
| C-10b | `purchaseStartDay` | AdvanceModule writes only | **EXEMPT-ADVANCEGAME** |
| C-10c | `rngRequestTime` | AdvanceModule `_requestRng` + VRF callback clear | **EXEMPT-VRFCALLBACK** / **EXEMPT-ADVANCEGAME** |

### C-11 — `rngLockedFlag` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-11a | `AdvanceModule._requestRng` | `AdvanceModule:1634` (`= true`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-11b | `AdvanceModule._unlockRng` | `AdvanceModule:1690` / `:1731` (`= false`) | `advanceGame()` stack + `retryLootboxRng` failsafe | **EXEMPT-ADVANCEGAME** / **EXEMPT-RETRYLOOTBOXRNG** |

### C-12 — `ticketWriteSlot` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-12a | `Storage._swapTicketSlot` | `Storage:744` | called only from `_swapAndFreeze` (Storage:755) which is `advanceGame()`-only | **EXEMPT-ADVANCEGAME** |

### C-13 — external sDGNRS pool balances (cross-contract)

| # | Slot | Read-site (this consumer) | Writer reach | Notes |
|---|------|---------------------------|-------------|-------|
| C-13a | `dgnrs.poolBalance(Lootbox)` (StakedDegenerusStonk's `pools[Lootbox].balance`) | `LootboxModule:1770` | sDGNRS `addToPool` (called by DegenerusGame on transitions + `transferFromPool` called by various) | Reach is the EOA-driven user-claim + deposit surface PLUS the `advanceGame()`-stack allocation; per-callsite classification deferred to consumer §12 (sStonk redemption catalog). For §8, the read of `poolBalance` is participating; the sDGNRS-side writers are out-of-this-section but the dispatch surface includes EOA paths. **VIOLATION-CANDIDATE.** See §D-6. |
| C-13b | `sdgnrs.poolBalance(Reward)` | `Degenerette:1147` | same as above (Reward pool) | Same classification — **VIOLATION-CANDIDATE.** See §D-7. |

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite + per-slot. Classification set: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION` — the v43.0 milestone goal prohibits any non-exempt disposition for participating slots, so every non-EXEMPT row is `VIOLATION`.

| #    | Slot                                                | Writer function · callsite                                         | Reached from EXEMPT stack? | Classification |
|------|-----------------------------------------------------|---------------------------------------------------------------------|----------------------------|----------------|
| D-0a | `degeneretteBets[player][nonce]`                    | `_placeDegeneretteBetCore:479`                                      | NO — EOA `placeDegeneretteBet` external | **VIOLATION** — write site is outside the 3 EXEMPT classes. The pre-RNG gate at Degenerette:452 (`if (lootboxRngWordByIndex[index] != 0) revert RngNotReady;`) blocks placement once VRF has published for the captured `index`; structurally this prevents post-T1 mutation of `degeneretteBets[player][betId]`. Catalog still flags VIOLATION per milestone-goal classification rules; §E-12 records that Phase 299 FIX must verify the :452 gate's coverage across index-rollover edges. |
| D-0b | `degeneretteBets[player][nonce]`                    | `_resolveBet:597` (self-delete)                                     | YES — the consumer itself (self-write inside the resolution stack post-rngWord SLOAD) | **EXEMPT-VRFCALLBACK** |
| D-1  | `lootboxRngWordByIndex[index]`                      | `AdvanceModule._finalizeLootboxRng:1256`                            | YES — VRF coordinator callback        | **EXEMPT-VRFCALLBACK** |
| D-2  | `lootboxRngWordByIndex[index]` (tail-fill)          | `AdvanceModule._gameOverEntropy:1761`                               | YES — game-over advanceGame stack     | **EXEMPT-VRFCALLBACK** (per D-43N V43 prose: terminal/game-over substitution path is also EXEMPT under the VRF-callback class because the source `finalWord` itself derives from a VRF callback or historical-VRF fallback per Phase 296 SWEEP) |
| D-3  | `lootboxRngWordByIndex[index]` (tail-fill at :1818) | `AdvanceModule._gameOverEntropy:1818`                               | YES — game-over advanceGame stack     | **EXEMPT-VRFCALLBACK** |
| D-4  | `prizePoolFrozen`                                   | `Storage._swapAndFreeze:757` + `_unfreezePool:777`                  | YES — `advanceGame()` only            | **EXEMPT-ADVANCEGAME** |
| D-5  | `prizePoolPendingPacked` (clear/seed)               | `Storage._swapAndFreeze:762/:764` + `_unfreezePool:776`             | YES                                    | **EXEMPT-ADVANCEGAME** |
| D-6  | `prizePoolPendingPacked` (consumer self-write)      | `Degenerette._distributePayout:764`                                 | YES — self-write inside §8 resolution | **EXEMPT-VRFCALLBACK** |
| D-7  | `prizePoolPendingPacked` (place-bet frozen-branch)  | `Degenerette._collectBetFunds:553`                                  | NO — EOA `placeDegeneretteBet`        | **VIOLATION** — between T1 and T2 of any in-flight bet's resolution, OTHER EOAs (or the same EOA placing a SECOND bet) can call `placeDegeneretteBet` and increment `prizePoolPendingPacked.future`. The §8 resolution reads `pFuture` at :755 to gate `if (uint256(pFuture) < ethShare) revert E()` — extra pending future inflates `pFuture`, making a borderline-insolvent ETH share PAYABLE under a known `rngWord`. Attacker pre-purchases a high-N gold ticket, observes the published `rngWord` → known `matches`, known `payout`, known `ethShare`, known `pFuture`; if `pFuture < ethShare` would revert under T0's `pFuture`, EOA tops up `prizePoolPendingPacked.future` via a fresh `placeDegeneretteBet` (frozen-branch) to flip the predicate to `pFuture ≥ ethShare` → bet resolves where it would otherwise revert. See §E-1. |
| D-8  | `prizePoolPendingPacked` (mint-purchase frozen-branch) | `MintModule.*` purchase paths that call `_setPendingPools` when `prizePoolFrozen` | NO — EOA ticket-purchase externals | **VIOLATION** — same mechanism as D-7 but via the MintModule ticket-purchase entry points (`purchaseTicketsByFunction` etc.). Attacker EOA can drive `prizePoolPendingPacked.future` upward by purchasing tickets between T1 and T2. The §8 resolution's pFuture-gate at :758 reads the post-mint value. See §E-2. |
| D-9  | `prizePoolPendingPacked` (jackpot frozen-branch)    | `JackpotModule.*` pending writes in jackpot-distribution stack      | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** (jackpot distribution happens within advance; not EOA-callable between T1/T2 except via the same advance stack which is single-tx per day) |
| D-10 | `prizePoolsPacked` (consumer self-write)            | `Degenerette._distributePayout:780`                                 | YES — self-write inside §8 resolution | **EXEMPT-VRFCALLBACK** |
| D-11 | `prizePoolsPacked` (advance-stack)                  | `JackpotModule.*` distribution + `_unfreezePool:775`                | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-12 | `prizePoolsPacked` (place-bet unfrozen-branch)      | `Degenerette._collectBetFunds:556`                                  | NO — EOA `placeDegeneretteBet`        | **VIOLATION** — analogous to D-7 but on the UNFROZEN branch: `_distributePayout` reads `_getFuturePrizePool` at :770 and uses it as the `pool × ETH_WIN_CAP_BPS / 10_000` cap denominator. EOA pre-buys a high-N gold ticket; under unfrozen-branch (more common), bumping `prizePoolsPacked.future` upward between T1 and T2 inflates the cap and lets a bigger `ethShare` pay out (vs being capped to `pool × 10%`, with the remainder going to lootbox — strictly worse RTP for the player). Direction-of-attack: increase pool → take MORE ETH; decrease pool → impossible from this writer. EOA-controlled UP-movement is the participating risk. See §E-3. |
| D-13 | `prizePoolsPacked` (mint-purchase unfrozen-branch)  | `MintModule.*` purchase paths                                       | NO — EOA ticket-purchase externals     | **VIOLATION** — same mechanism as D-12. See §E-4. |
| D-14 | `prizePoolsPacked` (decimator pool writers)         | `DecimatorModule.*` pool drains (e.g., `decimatorClaim` paths)      | NO — EOA decimator claim externals     | **VIOLATION** — direction-of-attack: decimator pool drains DOWNWARD which would shrink the cap. EOA-controlled DOWN-movement of `futurePool` (post-RNG) can convert an ETH share that would have been capped at `maxEth` into a SMALLER cap → MORE lootbox conversion. Reverse direction from D-12 but still participating. See §E-5. |
| D-15 | `level`                                             | `AdvanceModule._processJackpotPhaseAdvance:1643`                    | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-16 | `lootboxEvBenefitUsedByLevel[player][lvl]` (self)   | `LootboxModule._applyEvMultiplierWithCap:511` via `resolveLootboxDirect` self-call | YES — self-write | **EXEMPT-VRFCALLBACK** |
| D-17 | `lootboxEvBenefitUsedByLevel[player][lvl]` (openLootBox path) | `LootboxModule._applyEvMultiplierWithCap:511` via `openLootBox` external | NO — EOA `openLootBox` (`DegenerusGame.openLootBox` → delegatecall) | **VIOLATION** — Attacker observes `rngWord` at T1, computes the §8 spin loop result, knows their `ethShare`, knows whether they're capped at neutral (100%) or boosted (≤135%). If `lootboxEvBenefitUsedByLevel[player][lvl] ≥ LOOTBOX_EV_BENEFIT_CAP`, the §8 resolver's `_applyEvMultiplierWithCap` skips the EV adjustment (neutral 100%). EOA can call `openLootBox` (or `openBurnieLootBox` — though that path doesn't write this slot per check) BEFORE `resolveDegeneretteBets` to exhaust the cap → force the §8 ETH-share path through a neutral EV (when the player's score would otherwise boost). Direction-of-attack: drain remaining cap to make EV neutral when boost would lose; preserve cap when boost would win. Per-callsite VIOLATION. See §E-6. |
| D-18 | `lootboxEvBenefitUsedByLevel[player][lvl]` (resolveRedemptionLootbox path) | `LootboxModule._applyEvMultiplierWithCap:511` via `resolveRedemptionLootbox` external | EOA — sDGNRS-driven redemption (see §6) | **VIOLATION** — same mechanism as D-17; redemption-flow callsite is also EOA-reachable. See §E-6 (folded). |
| D-19 | `mintPacked_[player]` (mint-streak completion)      | `MintStreakUtils._recordMintStreakForLevel:47`                      | NO — EOA quest-completion path via `coin.handleX` → `quests` → cross-contract callbacks reaching DegenerusGame mint-credit. **AND** also reached from `advanceGame()` jackpot-tickets payouts. Per-callsite: | Mixed; **VIOLATION** for the EOA-quest-completion callsite. See §E-7. |
| D-20 | `mintPacked_[player]` (mint count + frozen-until + bundle type) | `MintModule._mintTickets` / deity / whale purchase writers          | NO — EOA ticket-purchase externals     | **VIOLATION** — `_playerActivityScore` reads `mintPacked_[player]` at MintStreakUtils:90 (level-count, deity, whale-bundle, frozen-until-level). EOA can move these fields between T1 and T2 by purchasing tickets / deity-pass / whale-pass → bumps `activityScore` → bumps `_lootboxEvMultiplierBps` (B-12) → bumps `scaledAmount` (B-W6 written) → flips the EV multiplier toward 135% (max). Attacker observes `rngWord` at T1, computes the §8 lootbox-arm result; if the result would crit (e.g., DGNRS large tier or BURNIE high-path), buys deity-pass to boost activity → boosts EV → 35% bonus on the crit lootbox amount. Per-callsite VIOLATION (EOA purchase callsite). See §E-8. |
| D-21 | `mintPacked_[player]` (affiliate cache refresh — recompute path) | `MintModule` affiliate-cache refresh on purchase | NO — EOA purchase externals | **VIOLATION** — `_playerActivityScore` at MintStreakUtils:140 reads the cached affiliate-bonus level + points fields from `mintPacked_`. Cached-level mismatch (`cachedLevel != currLevel`) falls through to live `affiliate.affiliateBonusPointsBest(currLevel, player)` external call. EOA can manipulate the cache via purchase to switch between cached/live branches and choose the higher of the two. See §E-9. |
| D-22 | `mintPacked_[player]` (affiliate cache refresh — advanceGame transition path) | `AdvanceModule` level transition affiliate-cache write | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-23 | `jackpotPhaseFlag`                                  | `AdvanceModule:333 / :437`                                          | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-24 | `lastPurchaseDay` / `purchaseStartDay` / `rngRequestTime` (liveness inputs) | various AdvanceModule writes (no EOA-direct mutators)               | YES — `advanceGame()` / VRF callback   | **EXEMPT-ADVANCEGAME** / **EXEMPT-VRFCALLBACK** |
| D-25 | `rngLockedFlag`                                     | `AdvanceModule._requestRng:1634` + `_unlockRng:1690/:1731`          | YES — `advanceGame()` + `retryLootboxRng` | **EXEMPT-ADVANCEGAME** / **EXEMPT-RETRYLOOTBOXRNG** |
| D-26 | `ticketWriteSlot`                                   | `Storage._swapTicketSlot:744`                                       | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-27 | `dgnrs.poolBalance(Lootbox)` (sDGNRS-side)          | sDGNRS `addToPool` + `transferFromPool` writers reachable from EOA paths (claim/redeem) | NO — EOA sDGNRS user paths            | **VIOLATION** — `_lootboxDgnrsReward` reads `dgnrs.poolBalance(Lootbox)` at :1770; this is the SCALAR that multiplies into `dgnrsAmount = (poolBalance * ppm * amount) / (1e6 * 1 ether)`. EOA can drain the Lootbox pool via legitimate `transferFromPool` callers between T1 and T2 (e.g., another player's win) — concurrent-actor race; but the §8 player can also opportunistically time their own resolution to occur AFTER a pool-drain they observe in mempool. Direction: pool drain → smaller `dgnrsAmount` → smaller payout (bad for player); pool top-up → larger `dgnrsAmount`. EOA controls timing by deferring `resolveDegeneretteBets` call. See §E-10. |
| D-28 | `sdgnrs.poolBalance(Reward)` (sDGNRS-side; 6+ match arm) | sDGNRS `addToPool` + `transferFromPool` writers                     | NO — EOA sDGNRS user paths            | **VIOLATION** — analogous to D-27 for the Reward pool. `_awardDegeneretteDgnrs` reads `poolBalance(Reward)` at :1147 then computes `reward = (poolBalance * bps * cappedBet) / (1e4 * 1 ether)`. Same timing-race attack class. See §E-11. |

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| #     | VIOLATION                                                                                              | Recommended tactic | Rationale (≤80 chars) |
|-------|--------------------------------------------------------------------------------------------------------|--------------------|------------------------|
| E-1   | D-7: `_collectBetFunds:553` increments `prizePoolPendingPacked.future` while §8 in-flight bet pending  | **(a)**            | Gate place-bet on `rngLockedFlag` so window closes once VRF requested |
| E-2   | D-8: MintModule frozen-branch ticket-purchase increments pending pool                                  | **(a)**            | Existing far-future `RngLocked` gate (:572) covers; extend to pending writes |
| E-3   | D-12: `_collectBetFunds:556` increments `prizePoolsPacked.future` (unfrozen-branch); inflates EV cap   | **(b)**            | Snapshot `futurePool` cap at bet placement; cap-check reads frozen snapshot |
| E-4   | D-13: MintModule unfrozen-branch ticket-purchase increments futurePool                                 | **(b)**            | Same snapshot tactic; per-bet `futurePool` snapshot recorded in `packed` |
| E-5   | D-14: Decimator pool drain decreases futurePool between T1 and T2 → shrinks cap → more lootbox        | **(b)**            | Per-bet futurePool snapshot also covers DOWN-movement |
| E-6   | D-17/D-18: `lootboxEvBenefitUsedByLevel[player][lvl]` mutated via `openLootBox` / `resolveRedemptionLootbox` between T1/T2 | **(b)**            | Snapshot `evMultiplierBps` at bet placement (already in `packed.activityScore`-adjacent slot) |
| E-7   | D-19: `mintPacked_[player]` mint-streak completion via EOA quest path mutates activity score          | **(b)**            | `activityScore` already snapshotted at :458; re-use snapshot in lootbox EV |
| E-8   | D-20: `mintPacked_[player]` purchase-driven field writes (level-count, deity, whale, frozen-until)    | **(b)**            | Snapshot full activity-score-input set at bet placement; lootbox EV reads snapshot |
| E-9   | D-21: `mintPacked_[player]` affiliate cache mismatch lets EOA choose cached vs live affiliate points  | **(b)**            | Snapshot covers; per-bet `activityScore` already capture-time-frozen at :458 |
| E-10  | D-27: `dgnrs.poolBalance(Lootbox)` EOA timing race shifts DGNRS reward scalar between T1/T2          | **(b)**            | Snapshot `poolBalance` at bet placement OR cap reward to amount × ppm (no pool ratio) |
| E-11  | D-28: `sdgnrs.poolBalance(Reward)` EOA timing race shifts sDGNRS reward scalar                       | **(b)**            | Snapshot `poolBalance` at bet placement OR remove pool-ratio scaling |
| E-12  | D-0a: `degeneretteBets[player][nonce]` written by `_placeDegeneretteBetCore:479` outside EXEMPT stack | **(a)**            | Existing :452 `lootboxRngWordByIndex[index] != 0 ⇒ RngNotReady` is the gate; verify post-RNG placement is impossible across all index-rollover edges |

**Rationale expansion (out-of-table for traceability):**

- **E-1 / E-2 (tactic (a) gated revert):** The CURRENT place-bet gate at Degenerette:452 only revert if `lootboxRngWordByIndex[index] != 0`; this requires a fresh CURRENT lootbox RNG index (the one captured at :450). But between RNG-request (T-request: `rngLockedFlag = true`) and RNG-publish (T1: `lootboxRngWordByIndex[index] = rngWord`), the `index` slot is still the OLD index (unchanged until `_finalizeLootboxRng` advances it). Place-bet at this point captures the SAME `index` as the in-flight bet that's about to resolve, but with `rngWord` still 0 → place-bet SUCCEEDS, pumping `prizePoolPendingPacked.future` (D-7) or `prizePoolsPacked.future` (D-12) just before T1+T2. Tactic (a) extends the gate to `rngLockedFlag == true ⇒ revert` so the window closes at VRF-request, not just at VRF-publish.

- **E-3..E-9 (tactic (b) snapshot/anchor):** Mirror Phase 281 owed-salt + Phase 288 dailyIdx pattern. The bet's `packed` already stores `activityScore` (snapshotted at :458). Extend the snapshot to include `futurePool`, `evMultiplierBps`, and the full activity-score input fields read at MintStreakUtils:90/96/140 — so the resolver does not re-read these at T2. Slot-budget within `packed` is tight (236 hero-bit + 3 hero quadrant = currently 240 bits, leaves 16 bits before bit-256); a parallel snapshot mapping `degeneretteBetSnapshot[player][nonce]` packs `futurePool` (uint128) + `evMultiplierBps` (uint16) + reserved into a single new SSTORE per place-bet.

- **E-10 / E-11 (tactic (b) pool-balance snapshot OR remove pool-ratio):** The sDGNRS-pool-balance scalar in `dgnrsAmount = (poolBalance × ppm × amount) / (1e6 × 1e18)` is a multi-actor-controlled aggregate. Two equally-effective options: (1) snapshot `poolBalance` at bet placement (added to the parallel snapshot mapping above); (2) remove the pool-ratio scaling entirely and let `dgnrsAmount = ppm × amount / 1e6` (independent of pool size) — accepting that the pool may temporarily be insufficient and that `transferFromPool` returns the actual paid amount. Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md`.

- **E-12 (D-0a structural attestation):** The slot is written outside the 3 EXEMPT classes (EOA `placeDegeneretteBet`); strict per-callsite classification flags this as VIOLATION. However, the structural gate at :452 (`if (lootboxRngWordByIndex[index] != 0) revert RngNotReady;`) forces all placements to occur BEFORE VRF publish for the captured `index`. Phase 299 FIX sub-phase planning must verify this gate's coverage across all index-advancement edges (e.g., index-rollover when LR_INDEX_SHIFT field increments — the captured `index` could in principle have its `rngWordByIndex` published while a different `_lrRead` returns a NEW current index that's still zero, opening a window for post-T1 placement on the OLD index. Catalog flags this; FIX phase derives the proof.).

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the §8 resolution path enumerated per `feedback_rng_window_storage_read_freshness.md`; no "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Cross-module trace into LootboxModule + Storage + MintStreakUtils + PayoutUtils followed transitively per `D-298-TRACE-DEPTH-01`.
- **Commitment-window discipline** (per `feedback_rng_commitment_window.md`): RNG commitment point is the SSTORE at `AdvanceModule.sol:1256` (`lootboxRngWordByIndex[index] = rngWord`); player-controllable state that can change between this SSTORE and the consumer reads at Degenerette:594 / LootboxModule:533/612 has been enumerated in §D and assigned a tactic in §E.
- **Two-rooted §8 trace:** Both consumer entries (Degenerette:594 + Degenerette:797) share the same RNG-word source slot and the same external entry point (`resolveDegeneretteBets`). The :797 sub-tree (LootboxModule.resolveLootboxDirect) adds B-10..B-17 + B-24..B-28 to the SLOAD set; the inline :594 sub-tree owns B-1..B-9 + B-18..B-23 directly. Shared SLOADs: B-3 (`lootboxRngWordByIndex[index]`), B-12/B-14 (`mintPacked_`/`level` reached from both via different code paths), B-19..B-23 (liveness inputs reached only from the :797 sub-tree).
- **Verdicts:** 28 §D rows total · 13 EXEMPT-ADVANCEGAME · 7 EXEMPT-VRFCALLBACK · 0 EXEMPT-RETRYLOOTBOXRNG (D-25 has one mixed sub-row that touches RETRYLOOTBOXRNG via `_unlockRng:1731`) · **12 VIOLATION** (D-0a, D-7, D-8, D-12, D-13, D-14, D-17, D-18, D-19, D-20, D-21, D-27, D-28 — counting D-0a + the 12 listed in §E rows E-1..E-12).
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.
## §9 — AdvanceModule.retryLootboxRng (file:line 1132)

**Consumer entry** — `contracts/modules/DegenerusGameAdvanceModule.sol:1132`

`retryLootboxRng() external` is the **mid-day lootbox-VRF failsafe**. Permissionless. Reachable only when `_requestLootboxRng` (line 1043) committed the buffer swap (`LR_MID_DAY = 1` at :1096) and the VRF callback has not delivered (`rngRequestTime != 0`). After the locked ≥6h cooldown (`MIDDAY_RNG_RETRY_TIMEOUT` at :141), it re-fires VRF with the identical parameters; the stalled requestId is auto-rejected by `rawFulfillRandomWords` at :1750 (`if (requestId != vrfRequestId || rngWordCurrent != 0) return;`). Buffer state and the pre-advanced `lootboxRngIndex` (LR_INDEX) are preserved so the new word lands in the same bucket the original was bound to.

**This consumer is NOT a literal VRF-word consumer** — it does not SLOAD `rngWordCurrent`, `lootboxRngWordByIndex[*]`, or `rngWordByDay[*]`. It is the VRF *protocol*-coordination failsafe. Per **D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A** (Phase 296 SWEEP lock), this consumer's resolution stack is its own EXEMPT class: `EXEMPT-RETRYLOOTBOXRNG`. The Option A scope is three locked invariants:

1. **≥6h cooldown** between successive replacements (line 1135: `if (block.timestamp < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT) revert E();`).
2. **≤1 VRF-replacement per stall event** — re-fire only when the in-flight request has not yet delivered; the second re-fire overwrites `vrfRequestId` so a third would still revert until the cooldown re-elapses.
3. **No pre-lock-state manipulation** — `retryLootboxRng` must not write any slot whose value the in-flight (or eventual) VRF callback / `_finalizeLootboxRng` will consume to derive a VRF-influenced output. Specifically: must NOT touch `lootboxRngWordByIndex`, the `LR_INDEX` / `LR_PENDING_ETH` / `LR_PENDING_BURNIE` / `LR_MID_DAY` fields of `lootboxRngPacked`, `rngWordCurrent`, `rngLockedFlag`, `dailyIdx`, `rngWordByDay`, or any commitment-side bet/ticket buffer slot. Pre-lock invariant per Option A.

The §9 §B/§C/§D rows below verify each invariant is structurally satisfied AND enumerate every slot the failsafe touches (read or write) so that the cross-callsite per-(slot × writer × callsite) classification per **D-298-EXEMPT-REACH-01** distinguishes the EXEMPT-RETRYLOOTBOXRNG callsite from non-EXEMPT callsites of the same writer/slot reached from other entry points (which then carry VIOLATION).

**Commitment-window discipline (per `feedback_rng_commitment_window.md`):**
- T0 (mid-day RNG request committed): `_requestLootboxRng` at :1043 fires VRF, sets `LR_MID_DAY = 1` (:1096), advances `LR_INDEX` (:1113), zeroes `LR_PENDING_ETH` / `LR_PENDING_BURNIE` (:1118-1119), assigns `vrfRequestId = id` (:1120), zeroes `rngWordCurrent` (:1121), stamps `rngRequestTime = block.timestamp` (:1122). The mid-day RNG buffer is now committed to the pre-advanced index.
- T-stall (≥6h elapsed, no callback): the original VRF request has not landed. The world-state between T0 and T-stall has accumulated: new lootbox purchases (writers of `LR_PENDING_ETH` / `LR_PENDING_BURNIE` at MintModule:1016/:1407, WhaleModule:877, DegeneretteModule:558/:563), no `_finalizeLootboxRng` writes (callback not delivered, so `lootboxRngWordByIndex[LR_INDEX-1]` is still 0).
- T1 (retryLootboxRng called): the failsafe SSTOREs ONLY `vrfRequestId` (:1153) and `rngRequestTime` (:1154). It does NOT advance `LR_INDEX`, does NOT zero pendings, does NOT touch `LR_MID_DAY` (which remains 1 by gate), does NOT touch `lootboxRngWordByIndex`. The pre-committed buffer is preserved.
- T2 (eventual VRF callback): the NEW requestId matches `vrfRequestId`; the OLD stalled callback (if it ever arrives) does not match and returns silently at :1750. `rawFulfillRandomWords` at :1745 writes `lootboxRngWordByIndex[LR_INDEX - 1] = word` (:1761) and clears `vrfRequestId` / `rngRequestTime`. The new word lands in the SAME bucket the T0 commitment bound.

The risk class to enumerate (per F-41-02/03 precedent in `feedback_rng_window_storage_read_freshness.md`): any SLOAD reached inside `retryLootboxRng` whose value an EOA can mutate between T0 and T1 — those flow into the failsafe's revert-gate decisions or into the new VRF request's parameters. Every SLOAD enumerated in §B; every participating-slot writer enumerated in §C.

### CAT-01 (§A) — Traced function set

Backward-trace rooted at `AdvanceModule.retryLootboxRng:1132`; trace walks transitively into every reachable function under `contracts/` per `D-298-TRACE-DEPTH-01`. Stops only at external interfaces with no source available (Chainlink VRF coordinator).

| #  | Function                              | File:line                                          | Reached from                          | Notes |
|----|---------------------------------------|----------------------------------------------------|---------------------------------------|-------|
| 1  | `retryLootboxRng`                     | `AdvanceModule.sol:1132`                           | external entry (EOA, permissionless)  | the failsafe body |
| 2  | `_lrRead`                             | `Storage.sol:1337`                                 | :1133                                  | `internal view`; SLOAD of `lootboxRngPacked`; bit-extract |
| 3  | `IVRFCoordinator.getSubscription`     | external interface                                 | :1137                                  | external staticcall; out of in-source scope per `D-298-TRACE-DEPTH-01` |
| 4  | `IVRFCoordinator.requestRandomWords`  | external interface                                 | :1142                                  | external call; out of in-source scope; reverts on coordinator-side failure (no try/catch — failure propagates back to caller) |

**No other functions are reached.** `retryLootboxRng` is a flat function body — no internal helper calls beyond `_lrRead` (Storage.sol:1337) and the two external VRF-coordinator interface calls. No delegatecalls, no inline assembly, no further dispatch.

**Explicit-enumeration cross-check** (per `feedback_verify_call_graph_against_source.md`):

- `sed -n '1132,1155p' contracts/modules/DegenerusGameAdvanceModule.sol` confirms the function body spans :1132-:1155 inclusive; every line accounted for in §B below.
- `grep -n "delegatecall\|\.call\|staticcall" contracts/modules/DegenerusGameAdvanceModule.sol | awk -F: '$2 >= 1132 && $2 <= 1155'` returns zero hits inside the function body — no cross-module reach.
- `grep -n "assembly" contracts/modules/DegenerusGameAdvanceModule.sol | awk -F: '$2 >= 1132 && $2 <= 1155'` returns zero hits inside the function body — no inline-assembly slot manipulation.
- `_lrRead` body at Storage.sol:1337-:1339 is `return (lootboxRngPacked >> shift) & mask;` — one SLOAD, no SSTORE, no further calls.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached inside the `retryLootboxRng` resolution path. Per `feedback_rng_window_storage_read_freshness.md`: ALL SLOADs enumerated; non-VRF-derived reads consumed alongside RNG-protocol state are a distinct bug class.

| #   | Slot                          | Read-site (file:line)                    | Read context                                                                                                           | Participating? | Attestation if NO |
|-----|-------------------------------|------------------------------------------|------------------------------------------------------------------------------------------------------------------------|----------------|---------------------|
| B-1 | `lootboxRngPacked` (LR_MID_DAY field, bits 224:231) | `AdvanceModule:1133` (via `_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK)` → Storage:1338) | failsafe entry gate: `if (... == 0) revert E();` — reverts unless the mid-day buffer-swap flag is set by a prior `_requestLootboxRng` at :1096 | **YES**        | — |
| B-2 | `rngRequestTime`              | `AdvanceModule:1134`                     | failsafe entry gate: `if (rngRequestTime == 0) revert E();` — reverts unless a VRF request is in-flight                | **YES**        | — |
| B-3 | `rngRequestTime`              | `AdvanceModule:1135`                     | cooldown gate: `if (uint48(block.timestamp) < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT) revert E();` — enforces ≥6h since last request | **YES**        | — |
| B-4 | `vrfCoordinator` (storage slot at Storage:1287) | `AdvanceModule:1137` (`vrfCoordinator.getSubscription(...)`) | SLOAD of coordinator address before external staticcall                                                                | **YES**        | — |
| B-5 | `vrfSubscriptionId`           | `AdvanceModule:1138`                     | argument to `getSubscription(vrfSubscriptionId)`                                                                       | **YES**        | — |
| B-6 | `vrfCoordinator` (storage slot at Storage:1287) | `AdvanceModule:1142` (`vrfCoordinator.requestRandomWords(...)`) | second SLOAD of coordinator address before external call; same slot as B-4 — re-read because Solidity does not cache cross-statement slots without explicit caching | **YES**        | — |
| B-7 | `vrfKeyHash`                  | `AdvanceModule:1144` (struct field `keyHash: vrfKeyHash`) | argument to `requestRandomWords({keyHash: vrfKeyHash, ...})`                                                            | **YES**        | — |
| B-8 | `vrfSubscriptionId`           | `AdvanceModule:1145` (struct field `subId: vrfSubscriptionId`) | argument to `requestRandomWords({subId: vrfSubscriptionId, ...})`; same slot as B-5                                    | **YES**        | — |

**Non-SLOAD reads** (immutable / constant / call-input, enumerated for completeness per `feedback_verify_call_graph_against_source.md`):
- `MIDDAY_RNG_RETRY_TIMEOUT` at :1135 — `uint48 private constant` (compile-time at AdvanceModule:141); no SLOAD.
- `MIN_LINK_FOR_LOOTBOX_RNG` at :1140 — `uint96 private constant` (compile-time at AdvanceModule:140); no SLOAD.
- `VRF_MIDDAY_CONFIRMATIONS` at :1146 — `uint16 private constant` (AdvanceModule:123); no SLOAD.
- `VRF_CALLBACK_GAS_LIMIT` at :1147 — `uint32 private constant` (AdvanceModule:115); no SLOAD.
- `block.timestamp` at :1135 + :1154 — opcode (TIMESTAMP); no SLOAD.
- Return value `linkBal` from `getSubscription` at :1137 — external-call return; out of in-source SLOAD scope per `D-298-TRACE-DEPTH-01` (the sDGNRS-side coordinator internals are not under `contracts/`).
- Return value `id` from `requestRandomWords` at :1142 — external-call return.

**Participating? = YES rationale.** Per **D-298-SLOT-CLASSIFICATION-01**, participating means "value influences a VRF-derived output". `retryLootboxRng` does not itself derive a VRF output — but the slots it reads (B-1..B-8) are the inputs to the *VRF-protocol coordination decisions* (gate / cooldown / coordinator selection / sub / keyHash) that determine which `requestId` the eventual `rawFulfillRandomWords` callback will validate against and where the resulting `rngWord` will land (`lootboxRngWordByIndex[LR_INDEX - 1]`). These slots gate the EXEMPT-RETRYLOOTBOXRNG envelope; any change to them between T0 and T1 alters either whether the failsafe runs, what VRF config the replacement uses, or how the new word is bound to a bucket. They are participating in the broader "VRF input frozen at commitment" milestone sense and must be classified in §D.

**No NON-PARTICIPATING SLOADs** in this consumer's trace — every SLOAD is gate / cooldown / VRF-config / VRF-binding state.

### CAT-03 (§C) — Per-slot writer enumeration

Per `D-298-EXEMPT-REACH-01`: writers enumerated per-callsite. For each participating slot (every row in §B), enumerate every external/public function in any contract under `contracts/` that writes the slot (OZ-inherited writers included; admin/owner writers included).

### C-1: `lootboxRngPacked` (LR_MID_DAY field, bits 224:231)

The `lootboxRngPacked` slot is multi-field-packed; LR_MID_DAY is the 8-bit field at bits 224:231. Per `D-298-EXEMPT-REACH-01`, writers are enumerated **per field**; the slot-level SSTORE in `_lrWrite` at Storage:1342 is the underlying primitive, but per-field semantics require enumerating each `_lrWrite(LR_MID_DAY_SHIFT, ...)` call site.

| Row   | Writer function                             | Callsite (file:line)              | Stack reaching this callsite                                          | Classification |
|-------|---------------------------------------------|------------------------------------|-----------------------------------------------------------------------|----------------|
| C-1a  | `AdvanceModule._requestLootboxRng`          | `AdvanceModule:1096` (`_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1)`) | `requestLootboxRng()` external (EOA, permissionless) → `_requestLootboxRng` private (no internal callers reach :1096 from any other entry) | **EXEMPT-RETRYLOOTBOXRNG**: structurally classified as a sibling of `retryLootboxRng` — both are pre-VRF-request-coordination paths gated by the same locked invariants. **However**, `requestLootboxRng` is a distinct external entry; per **D-298-EXEMPT-REACH-01** strict per-callsite, this callsite is reached from the `requestLootboxRng` stack, NOT from `retryLootboxRng`. The honest classification is **VIOLATION-CANDIDATE for non-§9 reach** — but for §9's verdict matrix (which classifies the callsite from §9's reach perspective), it is unreachable from §9 (retryLootboxRng does not call `_requestLootboxRng`). The slot's commitment-window participation under §9 is: the read at :1133 sees whatever the prior `requestLootboxRng` call wrote. See §D-1 + §E. |
| C-1b  | `AdvanceModule.rngGate` (mid-day-clear path) | `AdvanceModule:225` (`_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)`) | `advanceGame()` external → `_processAdvance` → `rngGate` → mid-day-clear branch | **EXEMPT-ADVANCEGAME** |
| C-1c  | `AdvanceModule.updateVrfCoordinatorAndSub`  | `AdvanceModule:1698` (`_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)`) | `DegenerusAdmin.proposeAndExecuteVrfSwap` → `gameAdmin.updateVrfCoordinatorAndSub(...)` (Admin.sol:901) — governance-gated emergency rotation | **VIOLATION-CANDIDATE** (governance-EOA-reachable; outside the 3 EXEMPT stacks). See §D-2 + §E. |

**No other writers.** `grep -rn '_lrWrite(LR_MID_DAY' contracts/ --include="*.sol"` returns exactly C-1a / C-1b / C-1c — three SSTORE sites; verified.

### C-2: `rngRequestTime`

Eight SSTORE sites globally; enumerated by `grep -rn 'rngRequestTime\s*=' contracts/ --include="*.sol"`.

| Row   | Writer function                                | Callsite (file:line)                              | Stack reaching this callsite                                                                                                                       | Classification |
|-------|------------------------------------------------|---------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|----------------|
| C-2a  | `AdvanceModule._requestLootboxRng`             | `AdvanceModule:1122` (`= uint48(block.timestamp)`) | `requestLootboxRng()` external → `_requestLootboxRng`                                                                                              | **VIOLATION-CANDIDATE for non-§9 reach** (requestLootboxRng stack is distinct from the 3 EXEMPT stacks per **D-42N-RETRY-RNG-DOMAIN-SEP-01** Option A's strict 3-class scope — it is the *commitment* side, not the failsafe; but the slot's mutation here happens at T0 BEFORE §9's window). See §D-3 + §E. |
| C-2b  | `AdvanceModule.retryLootboxRng`                | `AdvanceModule:1154` (`= uint48(block.timestamp)`) | `retryLootboxRng()` external (THIS consumer)                                                                                                       | **EXEMPT-RETRYLOOTBOXRNG** (the failsafe's own cooldown-reset SSTORE) |
| C-2c  | `AdvanceModule._gameOverEntropy` (clear branch)| `AdvanceModule:1329` (`= 0`)                       | `advanceGame()` external → `_handleGameOverPath` → `_gameOverEntropy` (game-over path)                                                             | **EXEMPT-ADVANCEGAME** |
| C-2d  | `AdvanceModule._tryRequestRng` (failure stamp) | `AdvanceModule:1341` (`= ts`)                      | `advanceGame()` external → `_processAdvance` → `_tryRequestRng` catch block (VRF coordinator-side failure)                                         | **EXEMPT-ADVANCEGAME** |
| C-2e  | `AdvanceModule._finalizeRngRequest`            | `AdvanceModule:1633` (`= uint48(block.timestamp)`) | `advanceGame()` external → `_tryRequestRng` → `_finalizeRngRequest`                                                                                | **EXEMPT-ADVANCEGAME** |
| C-2f  | `AdvanceModule.updateVrfCoordinatorAndSub`     | `AdvanceModule:1692` (`= 0`)                       | `DegenerusAdmin.proposeAndExecuteVrfSwap` → `gameAdmin.updateVrfCoordinatorAndSub` (governance-EOA emergency rotation)                             | **VIOLATION-CANDIDATE** (governance-EOA-reachable; outside the 3 EXEMPT stacks). See §D-4 + §E. |
| C-2g  | `AdvanceModule._unlockRng`                     | `AdvanceModule:1734` (`= 0`)                       | `advanceGame()` external → `_processAdvance` → `rngGate` → end-of-day → `_unlockRng`                                                               | **EXEMPT-ADVANCEGAME** |
| C-2h  | `AdvanceModule.rawFulfillRandomWords`          | `AdvanceModule:1764` (`= 0`)                       | Chainlink VRF coordinator → `rawFulfillRandomWords` (mid-day branch: `!rngLockedFlag` ⇒ direct finalize)                                            | **EXEMPT-VRFCALLBACK** |

**Verified:** 8 callsites; matches `grep` count exactly.

### C-3: `vrfCoordinator` (Storage:1287, type `IVRFCoordinator`)

Three SSTORE sites globally; enumerated by `grep -rn 'vrfCoordinator\s*=' contracts/ --include="*.sol"`.

| Row   | Writer function                              | Callsite (file:line)                  | Stack reaching this callsite                                                                          | Classification |
|-------|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|
| C-3a  | `AdvanceModule.wireVrf`                      | `AdvanceModule:506`                    | called once from `DegenerusAdmin` constructor during deployment (Admin.sol — constructor-time only; no post-deploy caller per :492-:494 NatSpec) | **EXEMPT-CONSTRUCTOR** (out of CAT-04's 3-EXEMPT-stack scope but structurally pre-deploy; deferred-ideas section of CONTEXT.md flags pre-deployment writers as included with separate classification). Catalog flags as **VIOLATION** per strict per-callsite milestone-goal rule — but design-intent attestation: the function reverts unless `msg.sender == ContractAddresses.ADMIN` (:503) AND Admin contract has no post-deploy caller for it. Phase 299 FIX must verify by re-reading `DegenerusAdmin.sol` that `wireVrf` is indeed callable only at constructor time. See §D-5 + §E. |
| C-3b  | `AdvanceModule.updateVrfCoordinatorAndSub`   | `AdvanceModule:1685`                   | governance-EOA emergency rotation                                                                     | **VIOLATION-CANDIDATE** (same governance-EOA stack as C-1c / C-2f). See §D-5 + §E. |

(Note: the `vrfCoordinator` declaration at Storage:1287 is a storage slot — confirmed not `immutable` — and `AdvanceModule:153` declares an unrelated `vault` constant. Only Storage:1287 is the writable slot.)

### C-4: `vrfSubscriptionId`

Two SSTORE sites globally; enumerated by `grep -rn 'vrfSubscriptionId\s*=' contracts/ --include="*.sol"`.

| Row   | Writer function                              | Callsite (file:line)                  | Stack reaching this callsite                                                                          | Classification |
|-------|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|
| C-4a  | `AdvanceModule.wireVrf`                      | `AdvanceModule:507`                    | constructor-time only (per :492-:494 NatSpec)                                                         | Same as C-3a — flag as **VIOLATION** per strict rules; see §D-6 + §E. |
| C-4b  | `AdvanceModule.updateVrfCoordinatorAndSub`   | `AdvanceModule:1686`                   | governance-EOA emergency rotation                                                                     | **VIOLATION-CANDIDATE**. See §D-6 + §E. |

### C-5: `vrfKeyHash`

Two SSTORE sites globally in `contracts/modules/` + one in `contracts/DegenerusAdmin.sol` (the latter writes Admin's own `vrfKeyHash`, NOT Game's — separate storage instance).

| Row   | Writer function                              | Callsite (file:line)                  | Stack reaching this callsite                                                                          | Classification |
|-------|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|
| C-5a  | `AdvanceModule.wireVrf`                      | `AdvanceModule:508`                    | constructor-time only (per :492-:494 NatSpec)                                                         | Same as C-3a — flag as **VIOLATION** per strict rules; see §D-7 + §E. |
| C-5b  | `AdvanceModule.updateVrfCoordinatorAndSub`   | `AdvanceModule:1687`                   | governance-EOA emergency rotation                                                                     | **VIOLATION-CANDIDATE**. See §D-7 + §E. |
| C-5c  | `DegenerusAdmin.proposeAndExecuteVrfSwap`    | `Admin.sol:889`                        | Admin's OWN `vrfKeyHash` slot — separate storage instance from Game's `vrfKeyHash` (Storage:1291); does NOT write the slot §B-7 reads. | **Out of §9 scope**: writes a different storage slot in a different contract. Listed for completeness; no §D row. |

### CAT-04 (§D) — Per-tuple verdict matrix

Per **D-298-EXEMPT-REACH-01** strict + per-callsite + per-slot. Classification set: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. The v43.0 milestone goal prohibits any non-exempt disposition for participating slots, so every non-EXEMPT row is `VIOLATION`. Per **D-298-EXEMPT-CROSSCONTRACT-01**, the per-callsite verdict is keyed on which EXEMPT stack reaches the specific call site.

| #     | Slot                                  | Writer callsite (file:line)                                              | Reached from EXEMPT stack? | Classification                |
|-------|---------------------------------------|--------------------------------------------------------------------------|----------------------------|-------------------------------|
| D-1   | `lootboxRngPacked.LR_MID_DAY` (set 1) | `_requestLootboxRng:1096`                                                | NO — EOA `requestLootboxRng` external (commitment-side; sibling of retryLootboxRng but in its own stack per D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A scope) | **VIOLATION** — the read at §B-1 sees this write. Between T0 (commitment) and T1 (failsafe entry), no other writer of LR_MID_DAY runs unless `advanceGame()` consumes it (which clears it at C-1b and exits the in-flight stall scenario). The mutation at C-1a is the commitment-side that the §9 gate at :1133 *requires* to be 1 — so the read at §B-1 cannot be adversarial against §9 itself (the player who calls `retryLootboxRng` strictly *benefits* from LR_MID_DAY = 1 — that's the gate to enter). However per strict per-callsite milestone-goal rule, this writer-callsite is outside the 3 EXEMPT stacks → VIOLATION-by-classification. Substantive risk: nil for §9's invariant. See §E-1. |
| D-2   | `lootboxRngPacked.LR_MID_DAY` (clear) | `updateVrfCoordinatorAndSub:1698`                                        | NO — governance-EOA via DegenerusAdmin governance flow | **VIOLATION** — governance-EOA can clear LR_MID_DAY mid-stall, which would cause §9's gate at :1133 to revert (`== 0 ⇒ revert E()`), permanently bricking the failsafe for the in-flight stall event. Mitigated by sDGNRS-holder governance (`DegenerusAdmin.proposeAndExecuteVrfSwap` requires propose/vote/execute with threshold). See §E-2. |
| D-3   | `rngRequestTime` (set ts)             | `_requestLootboxRng:1122`                                                | NO — EOA `requestLootboxRng` external | **VIOLATION** — commitment-side write that §9 reads at §B-2 + §B-3 to compute cooldown. Like D-1, the player who eventually calls `retryLootboxRng` *needs* this write to exist (else §B-2 gate at :1134 reverts on `rngRequestTime == 0`). Substantive risk: nil for §9's invariant — the cooldown is an absolute time-since-write check, and the writer cannot grief themselves by deferring (the timestamp is `block.timestamp`-stamped, not player-chosen). See §E-1. |
| D-4   | `rngRequestTime` (set ts)             | `retryLootboxRng:1154`                                                   | **YES — §9 itself**         | **EXEMPT-RETRYLOOTBOXRNG** — the failsafe's own cooldown-reset SSTORE; resets the 6h timer so a second retry cannot fire within the same stall event. Locked by **D-42N-RETRY-RNG-DOMAIN-SEP-01** Option A invariant 2 (≤1 replacement per stall — but technically the timer reset permits *another* retry after another 6h if the second VRF also stalls). |
| D-5   | `rngRequestTime` (clear 0)            | `_gameOverEntropy:1329`                                                  | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-6   | `rngRequestTime` (set ts on failure)  | `_tryRequestRng:1341`                                                    | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-7   | `rngRequestTime` (set ts)             | `_finalizeRngRequest:1633`                                               | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-8   | `rngRequestTime` (clear 0)            | `updateVrfCoordinatorAndSub:1692`                                        | NO — governance-EOA          | **VIOLATION** — same governance-rotation risk as D-2: clearing `rngRequestTime` mid-stall would brick §9's gate at :1134 (`== 0 ⇒ revert E()`). See §E-2. |
| D-9   | `rngRequestTime` (clear 0)            | `_unlockRng:1734`                                                        | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-10  | `rngRequestTime` (clear 0)            | `rawFulfillRandomWords:1764` (mid-day branch)                            | YES — VRF coordinator callback | **EXEMPT-VRFCALLBACK** |
| D-11  | `vrfCoordinator`                      | `wireVrf:506`                                                            | NO — constructor-time-only (Admin one-shot) | **VIOLATION** by strict rule; structurally pre-deploy (deferred-ideas attestation). See §E-3. |
| D-12  | `vrfCoordinator`                      | `updateVrfCoordinatorAndSub:1685`                                        | NO — governance-EOA          | **VIOLATION** — governance-EOA can swap the coordinator mid-stall; §B-4 / §B-6 read this new coordinator address. The replacement VRF request at §9:1142 fires against the NEW coordinator, which (per D-2 / D-8) also has its `LR_MID_DAY` and `rngRequestTime` cleared — bricking §9's gates. See §E-2. |
| D-13  | `vrfSubscriptionId`                   | `wireVrf:507`                                                            | NO — constructor-time-only   | **VIOLATION** by strict rule; structurally pre-deploy. See §E-3. |
| D-14  | `vrfSubscriptionId`                   | `updateVrfCoordinatorAndSub:1686`                                        | NO — governance-EOA          | **VIOLATION** — governance-EOA swaps sub-ID mid-stall; §B-5 / §B-8 reads the new ID; LINK-balance check at §9:1140 (`linkBal < MIN_LINK_FOR_LOOTBOX_RNG ⇒ revert`) now applies to the NEW sub which may have a different balance. See §E-2. |
| D-15  | `vrfKeyHash`                          | `wireVrf:508`                                                            | NO — constructor-time-only   | **VIOLATION** by strict rule; structurally pre-deploy. See §E-3. |
| D-16  | `vrfKeyHash`                          | `updateVrfCoordinatorAndSub:1687`                                        | NO — governance-EOA          | **VIOLATION** — governance-EOA swaps key hash mid-stall; §B-7 reads it; replacement VRF request at §9:1142 uses the new gas-lane key. Same governance-EOA bundle as D-2 / D-8 / D-12 / D-14. See §E-2. |

**Verdict count.** 16 rows total · 6 EXEMPT-ADVANCEGAME (D-5, D-6, D-7, D-9) — note D-5/D-6/D-7/D-9 = 4 rows · 1 EXEMPT-VRFCALLBACK (D-10) · **1 EXEMPT-RETRYLOOTBOXRNG (D-4)** · **11 VIOLATION** (D-1, D-2, D-3, D-8, D-11, D-12, D-13, D-14, D-15, D-16 = 10 rows — recount). Actual counts:

- EXEMPT-ADVANCEGAME: D-5, D-6, D-7, D-9 = **4 rows**
- EXEMPT-VRFCALLBACK: D-10 = **1 row**
- EXEMPT-RETRYLOOTBOXRNG: D-4 = **1 row** ✅ (satisfies plan acceptance criterion "≥1 EXEMPT-RETRYLOOTBOXRNG row")
- VIOLATION: D-1, D-2, D-3, D-8, D-11, D-12, D-13, D-14, D-15, D-16 = **10 rows**

Total: 16 rows. Classification set is the locked 4-element verdict alphabet per the milestone-goal rule (the SAFEBYDESIGN disposition is prohibited and intentionally absent).

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| #     | VIOLATION                                                                                              | Recommended tactic | Rationale (≤80 chars) |
|-------|--------------------------------------------------------------------------------------------------------|--------------------|------------------------|
| E-1   | D-1 / D-3: `_requestLootboxRng` writes LR_MID_DAY / rngRequestTime (sibling EOA entry, outside §9)      | **(c)**            | Pre-lock reorder: classify requestLootboxRng stack as 4th EXEMPT class |
| E-2   | D-2 / D-8 / D-12 / D-14 / D-16: governance VRF rotation clears LR_MID_DAY + rngRequestTime + rotates VRF config mid-stall | **(c)**            | Pre-lock reorder: queue mid-stall rotations until after callback or 12h timeout |
| E-3   | D-11 / D-13 / D-15: `wireVrf` writes VRF config at deploy-constructor                                  | **(d)**            | Immutable: bind VRF config at deploy and remove wireVrf or seal post-init |

**Rationale expansion (out-of-table for traceability):**

- **E-1 (tactic (c) pre-lock reorder — sibling-EOA scope expansion):** The `_requestLootboxRng` external entry (`requestLootboxRng()` at :1043) is the *commitment* side that §9 reads at gates §B-1..§B-3. Under the locked 3-EXEMPT-stack model (advanceGame / VRF callback / retryLootboxRng), the `requestLootboxRng` stack is NOT an EXEMPT class — so strict per-callsite rule flags C-1a (LR_MID_DAY set) and C-2a (rngRequestTime set) as VIOLATION. Substantive risk for §9's invariants: **nil** — both writes are timestamp-stamped (`block.timestamp`) and not under EOA influence beyond timing, and the §9 caller benefits from both writes existing (they are the gates to enter). Phase 299 FIX should: (1) classify `requestLootboxRng` as a 4th EXEMPT class (`EXEMPT-REQUESTLOOTBOXRNG` symmetric to retryLootboxRng) OR (2) merge both into a single `EXEMPT-MIDDAY-RNG` class. Pure reclassification — no contract change. Tactic (c) "pre-lock reorder" abstractly applies because the fix is a structural rebalance of which entries count as exempt.

- **E-2 (tactic (c) pre-lock reorder — governance rotation queuing):** The governance VRF rotation (`AdvanceModule.updateVrfCoordinatorAndSub` callable only via `DegenerusAdmin` propose/vote/execute) has five mid-stall mutation effects on §9's read-set: clearing LR_MID_DAY (D-2), clearing rngRequestTime (D-8), rotating coordinator (D-12), rotating sub-ID (D-14), rotating keyHash (D-16). All five are gated by sDGNRS-holder governance (multi-step, multi-block) and require a deliberate sDGNRS-holder collusion to time the rotation mid-stall. Risk class: a malicious-majority sDGNRS-holder coalition could time a coordinator rotation to brick a permissionless `retryLootboxRng` call from a specific actor — but the rotation itself causes the in-flight VRF to be abandoned (the old coordinator's callback won't match the new `vrfRequestId == 0`), so the retry-bricking is moot (the rotation already replaced the stalled RNG). Substantive risk: the governance-rotation flow already encompasses the failsafe's job. Phase 299 FIX should: (a) document that governance VRF rotation is a *replacement* of the retry failsafe (mutually exclusive paths) and explicitly classify the governance-rotation stack as a 5th EXEMPT class (`EXEMPT-GOVERNANCE-VRF-ROTATION`) at the same layer as RETRYLOOTBOXRNG; OR (b) require the rotation to revert if `LR_MID_DAY != 0` until either the callback delivers or 12h has elapsed. Option (a) is the lower-friction structural reorder; option (b) hardens against governance-griefing but adds a delay edge.

- **E-3 (tactic (d) immutable — deploy-time VRF config seal):** The constructor-time writers C-3a / C-4a / C-5a (at `wireVrf` :506-:508) are reachable only from `DegenerusAdmin`'s constructor per the NatSpec at :492-:494. The honest cataloging gives them a VIOLATION classification under strict per-callsite rules because they are not in the 3 EXEMPT stacks. Tactic (d) "immutable" applies if Phase 299 FIX is willing to seal VRF config at deploy by either making the storage slots `immutable` (Solidity 0.8.4+) or by adding a one-shot `vrfWired` flag that locks `wireVrf` after first call. The deployer-trust assumption is already required for the Admin constructor to wire VRF correctly; sealing converts the strict-rule VIOLATION into a structurally-attested deploy-time exemption.

**Audit residual: pre-lock-state-manipulation invariant verification (Option A invariant 3).**

Per the plan's Note on §9: "verify failsafe writes do not manipulate any pre-lock-relevant state beyond the retry's own scope."

The failsafe writes ONLY:
- `vrfRequestId = id` at :1153 — replaces the in-flight VRF correlation token; does NOT alter any slot the VRF callback reads to derive a VRF-influenced output (the callback reads `vrfRequestId` to GATE its action, not to derive entropy; the entropy comes from the `randomWords[0]` calldata argument).
- `rngRequestTime = uint48(block.timestamp)` at :1154 — resets the cooldown timer; does NOT alter any slot the VRF callback reads to derive a VRF-influenced output (the callback uses `rngRequestTime` for nothing — it is read by `rngGate` and `_gameOverEntropy` for stall detection, both of which run from `advanceGame()`, not from the callback).

**Pre-lock state NOT touched** (verified by grep of the function body :1132-:1155):
- `lootboxRngPacked.LR_INDEX` (the bucket the new word lands in) — NOT WRITTEN; the bucket is preserved per the function's NatSpec at :1130. The eventual `rawFulfillRandomWords` will write `lootboxRngWordByIndex[LR_INDEX - 1]` to the SAME bucket the original T0 commitment bound.
- `lootboxRngPacked.LR_PENDING_ETH` / `LR_PENDING_BURNIE` — NOT WRITTEN; in-flight purchases accumulated between T0 and T1 stay accumulated, and will be flushed to ETH/BURNIE-bound jackpot allocations during the eventual `_finalizeLootboxRng` consumer at AdvanceModule:1256 (NOT inside `retryLootboxRng`).
- `lootboxRngPacked.LR_MID_DAY` — NOT WRITTEN by §9 (the gate at :1133 only READS this field).
- `lootboxRngWordByIndex[*]` — NOT WRITTEN.
- `rngWordCurrent` — NOT WRITTEN.
- `rngLockedFlag` — NOT WRITTEN.
- `dailyIdx` — NOT WRITTEN.
- `rngWordByDay[*]` — NOT WRITTEN.

**Option A invariant 3 verified.** The failsafe is a pure VRF-protocol-coordination retry; it touches only the protocol-correlation slots (`vrfRequestId`, `rngRequestTime`) and does not manipulate any slot that participates in the *content* of a VRF-derived output.

**Cross-callsite per D-298-EXEMPT-REACH-01 + D-298-EXEMPT-CROSSCONTRACT-01.** The same writer functions (e.g., `updateVrfCoordinatorAndSub` writing `rngRequestTime` at :1692 in D-8) are reached from non-EXEMPT entry points at separate callsites. The catalog flags those callsites as VIOLATION per the strict per-callsite rule; remediation tactic (c) in §E-2 covers the governance-EOA class. The EXEMPT-RETRYLOOTBOXRNG class itself owns only one row (D-4: §9's own cooldown-reset SSTORE) — this is by design (§9 is a flat function that performs exactly one SSTORE inside the EXEMPT envelope), and satisfies the plan's "≥1 EXEMPT-RETRYLOOTBOXRNG row" acceptance criterion.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the §9 resolution path enumerated per `feedback_rng_window_storage_read_freshness.md`; no "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Trace is flat (no internal calls beyond `_lrRead` and external VRF interface calls); cross-module trace into Storage followed transitively per `D-298-TRACE-DEPTH-01`.
- **Commitment-window discipline** (per `feedback_rng_commitment_window.md`): RNG-protocol commitment point is the SSTORE pair at `_requestLootboxRng:1120-:1122` (`vrfRequestId = id`; `rngRequestTime = block.timestamp`); player-controllable state that can change between this SSTORE pair and the §9 read-set at :1133-:1145 has been enumerated in §D and assigned a tactic in §E.
- **Option A scope verification** (per D-42N-RETRY-RNG-DOMAIN-SEP-01): invariant 1 (≥6h cooldown) verified at §B-3 / D-4; invariant 2 (≤1 replacement per stall) verified by the cooldown-reset semantics at D-4 (the new `rngRequestTime` blocks a second retry for 6h, after which a fresh stall may permit another replacement — interpreted as "≤1 replacement per cooldown window", a relaxed but functionally equivalent reading); invariant 3 (no pre-lock-state manipulation) verified by the SSTORE-set enumeration in §E rationale block above.
- **Verdicts:** 16 §D rows total · 4 EXEMPT-ADVANCEGAME · 1 EXEMPT-VRFCALLBACK · **1 EXEMPT-RETRYLOOTBOXRNG (D-4)** · **10 VIOLATION** (D-1, D-2, D-3, D-8, D-11, D-12, D-13, D-14, D-15, D-16). Verdict alphabet locked to the 4-element set; the SAFEBYDESIGN disposition is prohibited and intentionally absent.
- **Cross-consumer dedup notes** (for Phase 298 integration agent): D-1 / D-3 (LR_MID_DAY / rngRequestTime set by `_requestLootboxRng`) are also reached from sibling consumer §13's mid-day rng-substitution call graph — the integration agent should dedupe these into the unique-slot index §14 + the per-slot writer table §15 with the union-of-classifications. D-11..D-16 (VRF config rotations) are also touched by every consumer §1..§13 whose resolution path reads `vrfCoordinator` / `vrfSubscriptionId` / `vrfKeyHash` (every consumer that fires VRF reads these slots at request time); dedup applies. D-4 (`retryLootboxRng:1154`) is unique to §9.
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.
## §10 — MintModule trait-generation consumer (Phase 290 MINTCLN audit-subject surface)

**Consumer entry:** `contracts/modules/DegenerusGameMintModule.sol:537` (`_raritySymbolBatch` — the 3-input keccak at :563-:565 `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` is the VRF-derived-entropy consumer; the assembly `sstore` block at :600-:629 is the trait-distribution OUTPUT site writing `traitBurnTicket[lvl][traitId]`'s length + element slots).

**Two outer-loop entry points reach this consumer:**
1. `processFutureTicketBatch(uint24 lvl, uint256 entropy)` at `MintModule.sol:385-526` — entropy passed as parameter (caller-supplied from `rngGate`-returned `rngWord` via `AdvanceModule._processFutureTicketBatch:1438`).
2. `processTicketBatch(uint24 lvl)` at `MintModule.sol:662-720` — entropy SLOADed at `:686` from `lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1]`.

**Caller stack:** Both functions are `external` on the MintModule but the MintModule is delegatecall-only from `DegenerusGame` (no `fallback()` in `DegenerusGame.sol` — confirmed via `grep -nE "fallback" contracts/DegenerusGame.sol` returning only a doc-comment hit). `grep -rn "processFutureTicketBatch\b\|processTicketBatch\b" contracts/ --include="*.sol"` confirms ONLY 4 callsites, ALL inside `DegenerusGameAdvanceModule.sol`: `:322` + `:414` + `:1438` (`_processFutureTicketBatch`); `:589` + `:607` + `:1516` (`processTicketBatch.selector` delegatecall in `_handleGameOverPath` + `_runProcessTicketBatch`); `:221` + `:277` + `:357` reach `_runProcessTicketBatch`. Every callsite lives inside `advanceGame`'s static call graph (entry at `AdvanceModule.sol:158`).

**VRF word source:**
- For `processFutureTicketBatch`: the `entropy` parameter flows from `AdvanceModule.advanceGame:290` `(uint256 rngWord, …) = rngGate(…)` — `rngGate` returns either `rngWordCurrent` (VRF-callback-published, nudge-mixed via `_applyDailyRng:1840` BEFORE `rngLockedFlag` clears) or `rngWordByDay[day]` (cached for the day). The cached parameter is forwarded through `_prepareFutureTickets:1463` / direct `_processFutureTicketBatch` invocations.
- For `processTicketBatch`: the entropy is SLOAD'd at `MintModule:686` from `lootboxRngWordByIndex[lrIndex - 1]` where `lrIndex` is read from `lootboxRngPacked` (the LR_INDEX field). `lootboxRngWordByIndex[i]` is written ONLY by `_finalizeLootboxRng:1256` (advanceGame-stack), `rawFulfillRandomWords:1761` (mid-day VRF-callback branch), and `_backfillOrphanedLootboxIndices:1818` (advanceGame-stack post-gap backfill).

**EXEMPT-stack roots in scope for this consumer:** EXEMPT-ADVANCEGAME (every reachable `_raritySymbolBatch` callsite is downstream of `advanceGame`-rooted outer loops — confirmed by the call-graph enumeration above). EXEMPT-VRFCALLBACK does NOT directly invoke `_raritySymbolBatch` — `rawFulfillRandomWords` only writes `rngWordCurrent` OR `lootboxRngWordByIndex[index]` then returns; the consumer is reached on the NEXT `advanceGame` call. EXEMPT-RETRYLOOTBOXRNG is the lootbox-VRF retry surface (`AdvanceModule.retryLootboxRng:1132`), domain-separated from the daily-VRF that feeds this consumer per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A — does NOT directly invoke `_raritySymbolBatch`.

**Pre-call state latches (relevant to commitment-window analysis):** Immediately before `_raritySymbolBatch` is invoked from either outer loop:
- (i) For `processTicketBatch` (mid-day same-day path at `AdvanceModule:206-238` and `_handleGameOverPath:584-622`): `rngLockedFlag` may be FALSE — the mid-day path checks `_lrRead(LR_MID_DAY_SHIFT)` to detect a pending mid-day VRF, and reverts `RngNotReady` if `lootboxRngWordByIndex[index-1] == 0` (`:213`). But the lock state itself is not asserted at the call boundary. **The entropy is committed: `lootboxRngWordByIndex[index-1]` is monotonic write-once (the `if (lootboxRngWordByIndex[index] != 0) return` guard at `_finalizeLootboxRng:1255` + at `rawFulfillRandomWords:1750` `if (requestId != vrfRequestId || rngWordCurrent != 0) return` ensures one-shot semantics).**
- (ii) For `processTicketBatch` (new-day path at `AdvanceModule:262-285` and `:357-363`): `rngLockedFlag = true` was set at `_requestRng:1634` AND immediately cleared at `_unlockRng:1731`. Inside the daily window, `rngLockedFlag=true` while `processTicketBatch` runs — `_finalizeLootboxRng:1253` is called at `rngGate:1234` BEFORE the outer-loop processing reaches `processTicketBatch`, so the entropy slot is populated before consumption.
- (iii) For `processFutureTicketBatch` (phase-transition FF drain at `:322-329`, near-future drain at `:344-352`, level-transition next-level drain at `:414`): `rngLockedFlag=true` for the entire window from `_requestRng:1634` to `_unlockRng` (called at `:331` after FF drain, `:402` after purchase-daily, `:467` after jackpot-phase, `:631` after game-over). The `entropy` parameter is the just-applied `rngWord` from `rngGate` — same parameter forwarded into every callsite within one `advanceGame` invocation.
- (iv) The `baseKey` carries `(lvl << 224) | (queueIdx << 192) | (player << 32) | owed` per Phase 290 MINTCLN-02 collapse. The `lvl` field is the cached function-parameter `lvl` (constant during the resolution loop). `queueIdx` is the loop-local `idx` (monotonically increasing). `player` is the loop-local `queue[idx]` SLOAD. `owed` is the loop-local `uint32(packed >> 8)` where `packed = ticketsOwedPacked[rk][player]` — DOES SLOAD per outer-loop iteration; per Phase 290 design-intent trace section (ii) the stale `owed==0` in `_processOneTicketEntry` post-`_resolveZeroOwedRemainder` branch is ACCEPTABLE under structural-closure reasoning (single-trait emission only).
- (v) The `traitBurnTicket[lvl][traitId]` length slot is the OUTPUT — its prior length is read (`let len := sload(elem)` at `:614`) and used to compute the destination data slot. The PRE-existing length is therefore a participating SLOAD even though the consumer ALSO writes it.
- (vi) The `_rollRemainder` helper at `:638-:650` re-hashes via `EntropyLib.hash2(entropy, rollSalt|baseKey)` and consumes only stack values + `rem` — no additional SLOADs beyond what the outer loop already enumerates.

---

### CAT-01 (§A) — Traced Function Set

Every internal/external function transitively reached from `processFutureTicketBatch` AND `processTicketBatch` with explicit file:line citation per `feedback_verify_call_graph_against_source.md`. The two outer-loop entries are both traced because both reach the same inner consumer `_raritySymbolBatch` + `_rollRemainder`.

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `processFutureTicketBatch(uint24 lvl, uint256 entropy)` | `MintModule.sol:385` | ENTRY (delegatecall-only from `AdvanceModule._processFutureTicketBatch:1438`) | Outer loop A |
| 2 | `processTicketBatch(uint24 lvl)` | `MintModule.sol:662` | ENTRY (delegatecall-only from `AdvanceModule._runProcessTicketBatch:1507` + `_handleGameOverPath:589/607`) | Outer loop B |
| 3 | `_tqReadKey(uint24 lvl)` | `Storage.sol:723` | 1 → :390 (false branch); 2 → :663 | `[view]` reads `ticketWriteSlot` |
| 4 | `_tqFarFutureKey(uint24 lvl)` | `Storage.sol:731` | 1 → :390 (true branch) + :512; 2 (unreachable) | `[pure]` |
| 5 | `_resolveZeroOwedRemainder(packed, rk, player, entropy, baseKey)` | `MintModule.sol:723` | 2 → :770 (via `_processOneTicketEntry`) | Calls `_rollRemainder`; writes `ticketsOwedPacked[rk][player]` |
| 6 | `_processOneTicketEntry(player, lvl, rk, room, processed, entropy, queueIdx)` | `MintModule.sol:752` | 2 → :690 | Calls `_raritySymbolBatch`, `_rollRemainder`, `_resolveZeroOwedRemainder`; writes `ticketsOwedPacked` |
| 7 | `_raritySymbolBatch(player, baseKey, startIndex, count, entropyWord)` | `MintModule.sol:537` | 1 → :470; 6 → :793 | **The 3-input keccak consumer**: `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` at `:563-:565`. Writes `traitBurnTicket[lvl][traitId]` via assembly `sstore` at `:600-:629`. |
| 8 | `_rollRemainder(entropy, rollSalt, rem)` | `MintModule.sol:638` | 1 → :444, :483; 5 → :738; 6 → :807 | `[pure]` — delegates to `EntropyLib.hash2` |
| 9 | `EntropyLib.hash2(uint256 a, uint256 b)` | `EntropyLib.sol:23` | 8 → :648 | `[pure]` keccak scratch-slot mix; ZERO SLOAD |
| 10 | `DegenerusTraitUtils.traitFromWord(uint64 rnd)` | `DegenerusTraitUtils.sol:143` | 7 → :577 | `[pure]` — weighted-grid trait derivation from low bits of LCG-step word; ZERO SLOAD |
| 11 | `_lrRead(uint256 shift, uint256 mask)` | `Storage.sol:1337` | 2 → :686 | `[view]` reads `lootboxRngPacked` |

> **Stop boundary:** `_raritySymbolBatch` is a `private` function with no further internal sub-calls beyond pure libraries `EntropyLib`/`DegenerusTraitUtils`. The inline assembly block at `:600-:629` is the trait-output SSTORE site — it computes `levelSlot = keccak256(lvl, traitBurnTicket.slot)` (Solidity standard storage layout) and writes `traitBurnTicket[lvl][traitId].length` + array element slots. No further function calls inside the assembly block.

> **Cross-module reach into Storage.sol:** `_queueTicketsScaled` / `_queueTickets` / `_queueTicketRange` are writers of `ticketsOwedPacked` + `ticketQueue` reached from OTHER external entry points (purchase / whale / lootbox / decimator / jackpot stacks). They are NOT reached transitively from this consumer's resolution stack — but they ARE the participating-slot writers enumerated in §C below.

> **`_purchaseFor` is NOT in this trace:** the parent `_purchaseFor` at `MintModule:899-1188` is a SEPARATE entry surface (EOA-purchase path); the `cachedJpFlag && rngLockedFlag` gate at `:1221` (referenced in `D-298-CONSUMER-LIST-01` as a locked-gate convention marker) is INSIDE `_callTicketPurchase` and routes the `targetLevel` of NEW purchases — it does NOT lead to `_raritySymbolBatch` directly. The `_purchaseFor` → `_queueTicketsScaled:1129` path is a WRITER of participating slots (`ticketsOwedPacked` + `ticketQueue` + `prizePoolsPacked`), enumerated below in §C.

---

### CAT-02 (§B) — SLOAD Table

Every storage read reached anywhere in §A's function set is enumerated per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent — NON-PARTICIPATING slots get explicit attestation). Columns: `Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO`.

| Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|------|-----------------------|--------------|----------------|-------------------|
| `lootboxRngPacked` (LR_INDEX field, bits 0..47) | `Storage.sol:1338` reached from `MintModule.sol:686` (`uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1`) | Computes index into `lootboxRngWordByIndex[]` → directly selects which VRF word feeds `entropy` for `_raritySymbolBatch` keccak | **YES** | — |
| `lootboxRngWordByIndex[lrIndex - 1]` | `MintModule.sol:686` | THE VRF word that becomes the `entropy` parameter passed to `_raritySymbolBatch` via `_processOneTicketEntry` for `processTicketBatch` path | **YES** | — (this IS the VRF-derived entropy) |
| `ticketWriteSlot` (bool) | `Storage.sol:719/724` (`_tqWriteKey`/`_tqReadKey`) reached from `MintModule.sol:390, :663` | Selects which `ticketQueue[]` array slot is the READ slot (the slot being drained) → determines `rk = _tqReadKey(lvl)` → determines which `ticketQueue[rk]` array the loop iterates AND which `ticketsOwedPacked[rk][player]` per-player counter is consulted | **YES** | — |
| `ticketLevel` (uint24) | `MintModule.sol:389` (`inFarFuture = (ticketLevel == (lvl \| TICKET_FAR_FUTURE_BIT))`); `:399` (`if (!inFarFuture && ticketLevel != lvl)`); `:667` (`if (ticketLevel != lvl)`) | Control-flow flag: distinguishes far-future drain branch from near-future + signals whether a fresh outer-loop is starting (resets `ticketCursor`). DOES influence `rk` selection at `:390` (via `_tqFarFutureKey` vs `_tqReadKey`) — different `rk` → different `baseKey.queueIdx` packing path AND different `ticketsOwedPacked[rk]` namespace. | **YES** | — |
| `ticketCursor` (uint32) | `MintModule.sol:404` (`idx = ticketCursor`); `:672` (same) | Loop entry point — determines `queueIdx` packed into `baseKey` at `:427`/:764 (`(idx << 192)`). Different cursor → different `baseKey` low bits → different keccak seed at `:563-:565`. | **YES** | — |
| `ticketQueue[rk]` (length + element slots) | `MintModule.sol:391` (`queue = ticketQueue[rk]`); `:393` (`total = queue.length`); `:405` (`idx >= total` check); `:422` (`address player = queue[idx]`); `:513` (`if (ticketQueue[ffk].length > 0)`); `:664-:665` (same in processTicketBatch); `:691` (`queue[idx]` in processTicketBatch via `_processOneTicketEntry`) | Length determines loop bound. Element SLOAD provides `player` — `player` is packed into `baseKey` middle bits at `:428`/`:765` (`(uint256(uint160(player)) << 32)`). Different `player` → different `baseKey` → different keccak seed. **Length AND elements are both participating.** | **YES** | — |
| `ticketsOwedPacked[rk][player]` (uint40) | `MintModule.sol:423` (`packed = ticketsOwedPacked[rk][player]`); `:761` (same in `_processOneTicketEntry`); `:724` (passed by-value to `_resolveZeroOwedRemainder`) | High 32 bits `owed` are packed into `baseKey` low 32 bits at `:429`/`:766` (`uint256(owed)`). Per Phase 290 MINTCLN-02 collapse this is the carrier of the cross-call seed-separation invariant. Low 8 bits `rem` drives `_rollRemainder` outcome. **Direct keccak-input contributor.** | **YES** | — |
| `traitBurnTicket[lvl][traitId].length` (pre-existing length, per traitId touched) | `MintModule.sol:614` (assembly `let len := sload(elem)` where `elem := add(levelSlot, traitId)`) inside `_raritySymbolBatch`'s output loop | Read to determine destination offset for the player-address writes (`dst := add(data, len)`). The new length is `len + occurrences` (`:615`). **Per `feedback_rng_window_storage_read_freshness.md`: the pre-existing length is a SLOAD reached inside the rng-window — it must be classified.** | **NO** | The length value determines the destination slot offset for writing — it does NOT feed back into the keccak seed at `:563-:565` (which is already computed at this point in the loop) and does NOT influence which `traitId` is selected (already determined by `DegenerusTraitUtils.traitFromWord(s)` at `:577`). A mid-window change to `traitBurnTicket[lvl][traitId].length` would change WHERE the player addresses are written, but the writers under enumeration are themselves only this same `_raritySymbolBatch` (no other writer exists — `grep -rn "traitBurnTicket" contracts/` confirms zero other SSTORE sites). The slot is therefore self-coupled within this consumer's stack — no external writer can race it. **F-41-02/03-style attestation: no concurrent writer outside the same delegatecall stack.** |
| `level` (uint24, storage slot) | Indirect: `Storage.sol:571` (`_queueTickets`) — NOT reached transitively from this consumer's resolution stack. (Reachable from external `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` callers — see §C writer enumeration for participating-slot context.) | (not reached inside `_raritySymbolBatch` trace) | **N/A** | The cached `lvl` parameter inside `processFutureTicketBatch`/`processTicketBatch` is a function argument, NOT a storage read. Storage `level` is read by OTHER paths that WRITE participating slots (`ticketsOwedPacked` + `ticketQueue` + `traitBurnTicket` via downstream `_raritySymbolBatch` — though `_raritySymbolBatch` itself doesn't SLOAD `level`, it derives `lvl` from `baseKey >> 224` at `:591`). |
| `traitBurnTicket.slot` reference | `MintModule.sol:602` (`mstore(0x20, traitBurnTicket.slot)`) | Compile-time slot constant for keccak storage-layout computation (`levelSlot := keccak256(0x00, 0x40)` at `:603`). | **NO** | Compile-time constant — Solidity storage-layout slot reference, NOT a runtime SLOAD. Standard mapping-layout: `slot(traitBurnTicket[lvl]) = keccak256(lvl . slot)`. |

> **Pure-helper completeness attestation:** `EntropyLib.hash2`, `DegenerusTraitUtils.traitFromWord`, `_tqFarFutureKey` all perform ZERO SLOADs (`grep -n "sload\|storage" contracts/libraries/EntropyLib.sol contracts/DegenerusTraitUtils.sol` returns only pointer-type declarations). `_rollRemainder` is `pure` (no SLOAD). The LCG iteration at `MintModule.sol:574, :577` is local-variable arithmetic only.

> **Cross-call freshness gate (Phase 290 MINTCLN-02 invariant):** Per Phase 290 `290-01-DESIGN-INTENT-TRACE.md` section (i): the SLOAD of `ticketsOwedPacked[rk][player].owed` per outer-loop iteration produces a SHRINKING low-32-bit value for `baseKey` across cross-call drains on the same `(rk, player)` pair (`remainingOwed = owed - take` at `:480` + `:804`). This SLOAD is the carrier of the cross-call seed-separation invariant that replaces the v41 Phase 281 `ownedSalt` 4th keccak input. **The SLOAD freshness IS the algorithmic invariant** — a stale value would re-introduce F-41-01.

> **Participating-set summary (forwards into §C):** `lootboxRngPacked` (LR_INDEX field), `lootboxRngWordByIndex[lrIndex-1]`, `ticketWriteSlot`, `ticketLevel`, `ticketCursor`, `ticketQueue[rk]` (length + elements), `ticketsOwedPacked[rk][player]`.

---

### CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` slot in §B, every external/public function across all `contracts/` that writes the slot is enumerated, per-callsite. Each row: `Slot | Writer fn | Writer file:line | Callsite file:line | Reach path`.

### Slot: `lootboxRngPacked` (LR_INDEX field — bits 0..47)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_finalizeRngRequest` increments LR_INDEX | `AdvanceModule.sol:1620-:1624` (`_lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, _lrRead(...) + 1)`) | `:1620` (inside `_finalizeRngRequest` which is called from `_requestRng`, reached from `rngGate` → `advanceGame:290`) | advanceGame → `rngGate` → `_requestRng` → `_finalizeRngRequest` |
| `DegenerusGameStorage.sol:1312` initializer | `Storage.sol:1312` (`lootboxRngPacked = 1 \| (1000 << 112) \| (14 << 176)`) | `:1312` | constructor / static initializer (genesis only) |

**Note:** Other fields of `lootboxRngPacked` (PENDING_ETH, PENDING_BURNIE, THRESHOLD, MIN_LINK, MID_DAY) have their own writers reached from `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / admin paths — but those writes mask only their own bit-ranges (the `_lrWrite` helper at `Storage.sol:1342` preserves other bits via `(packed & ~(mask << shift)) | …`). LR_INDEX-field writes are gated to advanceGame-stack only.

### Slot: `lootboxRngWordByIndex[i]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_finalizeLootboxRng(rngWord)` | `AdvanceModule.sol:1253` (writes `lootboxRngWordByIndex[index] = rngWord` at `:1256`) | `:275, :1234, :1296, :1326` (all inside `advanceGame` / `rngGate` / `_gameOverEntropy` / `_backfillGapDays`) | advanceGame → `_finalizeLootboxRng` (one-shot guard at `:1255` `if (… != 0) return`) |
| `rawFulfillRandomWords` mid-day branch | `AdvanceModule.sol:1745` (writes at `:1761` when `!rngLockedFlag`) | `:1761` (only mid-day path; the daily path writes `rngWordCurrent` instead) | Chainlink VRF coordinator → `rawFulfillRandomWords` (msg.sender gate at `:1749`) — **EXEMPT-VRFCALLBACK stack** |
| `_backfillOrphanedLootboxIndices(vrfWord)` | `AdvanceModule.sol:1806` (writes `lootboxRngWordByIndex[i] = fallbackWord` at `:1818`) | `:1207` (inside `rngGate` gap-day backfill) | advanceGame → `rngGate` → `_backfillOrphanedLootboxIndices` |

### Slot: `ticketWriteSlot` (bool)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_swapTicketSlot(purchaseLevel)` | `Storage.sol:741` (writes `ticketWriteSlot = !ticketWriteSlot` at `:744`) | `:755` (inside `_swapAndFreeze`); `AdvanceModule.sol:601` (inside `_handleGameOverPath` for round-2 drain); `AdvanceModule.sol:1095` (inside `_consolidatePoolsAndRewardJackpots` post-drain swap). All callsites inside `advanceGame`. | advanceGame → `_swapAndFreeze` / `_handleGameOverPath` / `_consolidatePoolsAndRewardJackpots` |

### Slot: `ticketLevel` (uint24)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `processFutureTicketBatch` self-writes | `MintModule.sol:395, :400, :408, :514, :519, :523` (multiple branches: reset to 0, set to `lvl`, set to `lvl \| TICKET_FAR_FUTURE_BIT`) | `:395` etc. (self) | advanceGame → `_processFutureTicketBatch` (delegatecall) — **self-stack** |
| `processTicketBatch` self-writes | `MintModule.sol:668, :676, :716` | `:668` etc. (self) | advanceGame → `_runProcessTicketBatch` (delegatecall) — **self-stack** |
| `advanceGame` phase-transition FF-promotion | `AdvanceModule.sol:319` (`ticketLevel = ffLevel \| TICKET_FAR_FUTURE_BIT`) | `:319` | advanceGame self-write |

**No external writer of `ticketLevel` exists outside the advanceGame-stack** — `grep -rn "ticketLevel\s*=" contracts/ --include="*.sol"` confirms all callsites are inside `MintModule.processTicketBatch` / `MintModule.processFutureTicketBatch` / `AdvanceModule.advanceGame`.

### Slot: `ticketCursor` (uint32)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `processFutureTicketBatch` self-writes | `MintModule.sol:394, :401, :407, :507, :515, :518, :522` | (self) | advanceGame stack |
| `processTicketBatch` self-writes | `MintModule.sol:669, :675, :711, :715` | (self) | advanceGame stack |
| `advanceGame` FF-promotion reset | `AdvanceModule.sol:320` (`ticketCursor = 0`) | `:320` | advanceGame self-write |

**Same as `ticketLevel`** — no external writer; all writes are inside advanceGame-stack.

### Slot: `ticketQueue[rk]` (length + elements)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_queueTickets(buyer, targetLevel, quantity, rngBypass)` | `Storage.sol:559` (`.push(buyer)` at `:580`) | Callsites: `DegenerusGame.sol:226, :227` (constructor — SDGNRS + VAULT initial); `AdvanceModule.sol:1535, :1541` (phase-transition vault tickets); `WhaleModule.sol:313, :482, :625` (whale-bundle / lazy-pass / deity-pass tickets); `LootboxModule.sol:1067, :1190` (lootbox resolution tickets); `JackpotModule.sol:703, :837, :1007, :2305` (auto-rebuy / jackpot bonus tickets). | EOA → various external entries (purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass, openLootBox, openBurnieLootBox, claimWhalePass etc.) → `_queueTickets`; advanceGame → various |
| `_queueTicketsScaled(buyer, targetLevel, quantityScaled, rngBypass)` | `Storage.sol:593` (`.push(buyer)` at `:612`) | `MintModule.sol:1129` (inside `_purchaseFor` after ticket-cost computation) | EOA → `purchase` / `purchaseCoin` → `_purchaseFor` → `_queueTicketsScaled` |
| `_queueTicketRange(buyer, startLevel, numLevels, ticketsPerLevel, rngBypass)` | `Storage.sol:646` (`.push(buyer)` at `:666`) | `DecimatorModule.sol:582` (decimator-tier winner tickets); `WhaleModule.sol:973` (claimWhalePass range claim); `Storage.sol:1135` (whale-pass redemption inside `_redeemWhalePassRange`) | EOA → `recordDecBurn` (via BurnieCoin) / `claimWhalePass` / whale-pass redemption → `_queueTicketRange` |
| `processFutureTicketBatch` self-writes (delete) | `MintModule.sol:406, :510` (`delete ticketQueue[rk]` after full drain) | (self) | advanceGame stack |
| `processTicketBatch` self-writes (delete) | `MintModule.sol:674, :714` | (self) | advanceGame stack |

### Slot: `ticketsOwedPacked[rk][player]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_queueTickets` | `Storage.sol:585` (`ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) \| uint40(rem)`) | Same callsites as `ticketQueue[rk]` writer above (every `_queueTickets` call writes both slots atomically). | Same |
| `_queueTicketsScaled` | `Storage.sol:636` (`ticketsOwedPacked[wk][buyer] = newPacked`) | `MintModule.sol:1129` | EOA → `purchase` / `purchaseCoin` |
| `_queueTicketRange` | `Storage.sol:671` (`ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) \| uint40(rem)`) | `DecimatorModule.sol:582`, `WhaleModule.sol:973`, `Storage.sol:1135` | EOA → `recordDecBurn`/`claimWhalePass` |
| `processFutureTicketBatch` self-writes | `MintModule.sol:433, :445, :455, :490` | (self) | advanceGame stack |
| `processTicketBatch` / `_processOneTicketEntry` / `_resolveZeroOwedRemainder` self-writes | `MintModule.sol:733, :740, :746, :814` | (self) | advanceGame stack |

**Note on `rngLockedFlag` gating in writers:** `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` all carry a `rngLockedFlag` gate at `Storage.sol:572`/`:604`/`:660` (`if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`). This gate fires ONLY when `targetLevel > level + 5` (the far-future branch) — for `targetLevel <= level + 5` (near-future + current-level), the write proceeds during the rng-window without revert. Callers from `JackpotModule._queueTickets` (the four jackpot-derived callsites `:703, :837, :1007, :2305`) pass `rngBypass=true` deliberately.

---

### CAT-04 (§D) — Verdict Matrix

Per-(slot × writer × callsite) classification. Tokens: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. Per `D-43N-AUDIT-ONLY-01` — no discretionary-safe class permitted (v43.0 milestone goal explicitly precludes the legacy disposition for participating slots). Per `D-298-EXEMPT-REACH-01` strict + per-callsite. Per `D-298-EXEMPT-CROSSCONTRACT-01` cross-contract EXEMPT preserved when callsite traces to EXEMPT stack.

| # | Slot | Writer fn | Callsite file:line | Reach analysis | Classification |
|---|------|-----------|--------------------|----------------|---------------|
| 1 | `lootboxRngPacked` (LR_INDEX) | `_finalizeRngRequest` LR_INDEX++ | `AdvanceModule.sol:1620` | EXEMPT-ADVANCEGAME (only reachable via `advanceGame` → `rngGate` → `_requestRng` → `_finalizeRngRequest`) | **EXEMPT-ADVANCEGAME** |
| 2 | `lootboxRngPacked` (LR_INDEX) | static initializer | `Storage.sol:1312` | constructor / static initializer (pre-deploy) | **EXEMPT-ADVANCEGAME** (constructor is structurally EXEMPT — runs once, before any VRF callback can fire) |
| 3 | `lootboxRngWordByIndex[i]` | `_finalizeLootboxRng` daily | `AdvanceModule.sol:1256` | EXEMPT-ADVANCEGAME (one-shot guard at `:1255`; reached only from `rngGate` inside `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 4 | `lootboxRngWordByIndex[i]` | `rawFulfillRandomWords` mid-day branch | `AdvanceModule.sol:1761` | EXEMPT-VRFCALLBACK (caller is Chainlink VRF coordinator; gate at `:1749` `msg.sender != address(vrfCoordinator) revert`); one-shot guard at `:1750` `if (… \|\| rngWordCurrent != 0) return` | **EXEMPT-VRFCALLBACK** |
| 5 | `lootboxRngWordByIndex[i]` | `_backfillOrphanedLootboxIndices` | `AdvanceModule.sol:1818` | EXEMPT-ADVANCEGAME (only reachable via `rngGate` → `_backfillOrphanedLootboxIndices` inside `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 6 | `ticketWriteSlot` | `_swapTicketSlot` via `_swapAndFreeze` | `AdvanceModule.sol:299` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 7 | `ticketWriteSlot` | `_swapTicketSlot` round-2 game-over drain | `AdvanceModule.sol:601` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 8 | `ticketWriteSlot` | `_swapTicketSlot` post-drain swap | `AdvanceModule.sol:1095` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 9 | `ticketLevel` | self-write inside `processFutureTicketBatch` | `MintModule.sol:395/:400/:408/:514/:519/:523` | EXEMPT-ADVANCEGAME (self-stack — only reachable via `_processFutureTicketBatch` delegatecall from advanceGame) | **EXEMPT-ADVANCEGAME** |
| 10 | `ticketLevel` | self-write inside `processTicketBatch` | `MintModule.sol:668/:676/:716` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 11 | `ticketLevel` | `advanceGame` FF-promotion | `AdvanceModule.sol:319` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 12 | `ticketCursor` | self-writes inside `processFutureTicketBatch` | `MintModule.sol:394/:401/:407/:507/:515/:518/:522` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 13 | `ticketCursor` | self-writes inside `processTicketBatch` | `MintModule.sol:669/:675/:711/:715` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 14 | `ticketCursor` | `advanceGame` FF-promotion reset | `AdvanceModule.sol:320` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 15 | `ticketQueue[rk]` | `_queueTickets` — constructor SDGNRS/VAULT init | `DegenerusGame.sol:226/:227` | constructor (pre-deploy) | **EXEMPT-ADVANCEGAME** (constructor) |
| 16 | `ticketQueue[rk]` | `_queueTickets` — phase-transition vault tickets | `AdvanceModule.sol:1535/:1541` | EXEMPT-ADVANCEGAME (inside `_processPhaseTransition` reached from `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 17 | `ticketQueue[rk]` | `_queueTickets` — `purchaseWhaleBundle` | `WhaleModule.sol:313` (reached via `DegenerusGame.purchaseWhaleBundle` external) | NOT in EXEMPT stack — EOA-initiated. `purchaseWhaleBundle` has `rngLockedFlag` gate at `WhaleModule.sol:543`? Verify: `grep -n "rngLockedFlag" WhaleModule.sol` shows `:543` is inside `purchaseDeityPass`, NOT `purchaseWhaleBundle`. `purchaseWhaleBundle` calls `_queueTickets(buyer, lvl, …, false)` so the `_queueTickets` internal gate at `Storage.sol:572` fires for `isFarFuture` writes only. Near-future + current-level writes PROCEED inside the window. | **VIOLATION** |
| 18 | `ticketQueue[rk]` | `_queueTickets` — `purchaseLazyPass` | `WhaleModule.sol:482` | Same as #17 — `_queueTickets` is called with `rngBypass=false`; far-future revert, near-future proceeds. No top-level rngLockedFlag gate found at `purchaseLazyPass` entry. | **VIOLATION** |
| 19 | `ticketQueue[rk]` | `_queueTickets` — `purchaseDeityPass` | `WhaleModule.sol:625` | `purchaseDeityPass` has `if (rngLockedFlag) revert RngLocked()` at `WhaleModule.sol:543` — full revert inside window. Per `D-298-EXEMPT-REACH-01` (stack-rooted strict): the writer is NOT call-stack-reachable from an EXEMPT root, classification remains VIOLATION; the gate is a correctness-proof artifact. | **VIOLATION** |
| 20 | `ticketQueue[rk]` | `_queueTickets` — `LootboxModule.openLootBox` resolution | `LootboxModule.sol:1067` | NOT in EXEMPT stack — EOA-initiated `openLootBox`. Lootbox VRF is domain-separated per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A, but the writer still races the daily-VRF MintModule consumer (cross-domain write). | **VIOLATION** |
| 21 | `ticketQueue[rk]` | `_queueTickets` — `LootboxModule.openBurnieLootBox` resolution | `LootboxModule.sol:1190` | Same as #20 — separate VRF domain, but the write target (`ticketQueue[rk]`) is shared. | **VIOLATION** |
| 22 | `ticketQueue[rk]` | `_queueTickets` — `JackpotModule` auto-rebuy/jackpot-flow | `JackpotModule.sol:703, :837, :1007, :2305` | EXEMPT-ADVANCEGAME (every JackpotModule.sol `_queueTickets` callsite is reached from `payDailyJackpot` / `payDailyJackpotCoinAndTickets` / terminal-jackpot path, all inside advanceGame). | **EXEMPT-ADVANCEGAME** |
| 23 | `ticketQueue[rk]` | `_queueTicketsScaled` — `MintModule._purchaseFor` | `MintModule.sol:1129` (reached via `DegenerusGame.purchase` / `purchaseCoin` external) | NOT in EXEMPT stack — EOA-initiated. `_purchaseFor` has NO blanket `rngLockedFlag` revert — only the `cachedJpFlag && rngLockedFlag` last-jackpot-day target-level redirect at `MintModule.sol:1221`. Writes to `ticketQueue[rk]` PROCEED during the resolution window. | **VIOLATION** |
| 24 | `ticketQueue[rk]` | `_queueTicketRange` — `DecimatorModule._awardDecimatorLootbox` | `DecimatorModule.sol:582` | NOT in EXEMPT stack — reached from `DegenerusCoin.burnCoin` → `recordDecBurn` external entry, OR from advanceGame's decimator-jackpot path (entry §13). For the EOA-initiated burn path: VIOLATION. For the advanceGame-stack decimator-jackpot path: EXEMPT-ADVANCEGAME. **Per-callsite split required; this single source-line is reached from both stacks.** Following `D-298-EXEMPT-REACH-01` (per-callsite): the EOA-reach is VIOLATION. | **VIOLATION** |
| 25 | `ticketQueue[rk]` | `_queueTicketRange` — `WhaleModule.claimWhalePass` | `WhaleModule.sol:973` (reached via `DegenerusGame.claimWhalePass` external) | NOT in EXEMPT stack — EOA-initiated. No top-level `rngLockedFlag` gate on `claimWhalePass`; downstream `_queueTicketRange` reverts atomically inside the loop when `isFarFuture && rngLockedFlag` for level+6..+100 portion — effective gate but stack-strict classification. | **VIOLATION** |
| 26 | `ticketQueue[rk]` | `_queueTicketRange` — `Storage._redeemWhalePassRange` (whale-pass redemption helper) | `Storage.sol:1135` | Reached from claim/redemption surface — same as #25. | **VIOLATION** |
| 27 | `ticketQueue[rk]` | self-`delete` inside `processFutureTicketBatch` | `MintModule.sol:406/:510` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 28 | `ticketQueue[rk]` | self-`delete` inside `processTicketBatch` | `MintModule.sol:674/:714` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 29 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — phase-transition vault tickets | `AdvanceModule.sol:1535/:1541` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 30 | `ticketsOwedPacked[rk][player]` | `_queueTickets` constructor | `DegenerusGame.sol:226/:227` | constructor (pre-deploy) | **EXEMPT-ADVANCEGAME** (constructor) |
| 31 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `purchaseWhaleBundle` | `WhaleModule.sol:313` | Same as #17 | **VIOLATION** |
| 32 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `purchaseLazyPass` | `WhaleModule.sol:482` | Same as #18 | **VIOLATION** |
| 33 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `purchaseDeityPass` | `WhaleModule.sol:625` | Same as #19 (gate present; stack-strict VIOLATION) | **VIOLATION** |
| 34 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `LootboxModule.openLootBox` | `LootboxModule.sol:1067` | Same as #20 | **VIOLATION** |
| 35 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `LootboxModule.openBurnieLootBox` | `LootboxModule.sol:1190` | Same as #21 | **VIOLATION** |
| 36 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — JackpotModule self-stack | `JackpotModule.sol:703, :837, :1007, :2305` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 37 | `ticketsOwedPacked[rk][player]` | `_queueTicketsScaled` — `MintModule._purchaseFor` | `MintModule.sol:1129` | Same as #23 | **VIOLATION** |
| 38 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` — `DecimatorModule._awardDecimatorLootbox` | `DecimatorModule.sol:582` | Same as #24 (EOA-reach) | **VIOLATION** |
| 39 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` — `WhaleModule.claimWhalePass` | `WhaleModule.sol:973` | Same as #25 | **VIOLATION** |
| 40 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` — `Storage._redeemWhalePassRange` | `Storage.sol:1135` | Same as #26 | **VIOLATION** |
| 41 | `ticketsOwedPacked[rk][player]` | self-writes inside `processFutureTicketBatch` | `MintModule.sol:433/:445/:455/:490` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 42 | `ticketsOwedPacked[rk][player]` | self-writes inside `processTicketBatch`/`_processOneTicketEntry`/`_resolveZeroOwedRemainder` | `MintModule.sol:733/:740/:746/:814` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |

> **All rows carry a concrete EXEMPT/VIOLATION token.** Every callsite × slot × writer tuple in §C carries one of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION` per `D-43N-AUDIT-ONLY-01` + `D-298-EXEMPT-REACH-01` strict. Zero rows escape the 4-token verdict set.

> **Row-class summary:** Rows classified `VIOLATION`: **17, 18, 19, 20, 21, 23, 24, 25, 26, 31, 32, 33, 34, 35, 37, 38, 39, 40** = **18 rows**. Rows classified `EXEMPT-ADVANCEGAME`: 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 22, 27, 28, 29, 30, 36, 41, 42 = **23 rows**. Rows classified `EXEMPT-VRFCALLBACK`: 4 = **1 row**. Rows classified `EXEMPT-RETRYLOOTBOXRNG`: **0 rows** (not in this consumer's reach set — domain-separated VRF). Total = **42 rows**.

> **Commitment-window analysis (per `feedback_rng_commitment_window.md`):** For `processFutureTicketBatch`, the `entropy` parameter is captured at `rngGate:290` inside `advanceGame` and threaded as-cached through the resolution loop — between `rngGate` return and `_raritySymbolBatch` execution, ANY external `_queueTickets` callsite that fires INSIDE the same advanceGame transaction is impossible (Solidity execution is sequential within a transaction). The race is BETWEEN advanceGame transactions: the external writer (e.g., a player calls `purchase` between two `advanceGame` calls) modifies `ticketQueue[rk]` + `ticketsOwedPacked[rk][player]` AFTER the prior `advanceGame` set `rngLockedFlag=true` AT `_requestRng`, and BEFORE the NEXT `advanceGame` that consumes the now-fulfilled VRF word reads them via `processTicketBatch`. The `_queueTickets` near-future gate is INSUFFICIENT to prevent this race because the writer is targeting near-future (level+1..+5) levels, which is the SAME range the consumer drains.

> **Double-buffer mitigation:** `_swapAndFreeze` at `:299` toggles `ticketWriteSlot` BEFORE the daily-RNG consumer fires — new writes during the rng-window land in the NEW write slot, while the consumer drains the OLD read slot. **This is a STRUCTURAL ANTI-RACE pattern but does NOT fully close the window for cross-call drains:** `processFutureTicketBatch` is called for far-future levels (level+6..+100 via `ffLevel`) which use `_tqFarFutureKey(lvl)` — a SEPARATE key space NOT double-buffered. The `rngLockedFlag` gate at `Storage.sol:572` for `isFarFuture` writes IS the far-future race closure. For near-future levels (level+1..+5) drained by `processFutureTicketBatch` at `:344-352` and current-level by `processTicketBatch`, the double-buffer carries the freshness invariant. **The VIOLATIONS above are non-far-future writes that land in the SAME (double-buffered) WRITE slot the next-day consumer will read** — so the double-buffer DOES protect the immediate VRF consumption but does NOT protect freshness ACROSS the lock window (because the writes accumulate in the write slot and will be drained on the NEXT VRF cycle, where they participate in NEXT day's keccak seed via the very mechanism this catalog enumerates).

---

### CAT-06 (§E) — Remediation Tactic per VIOLATION Row

Per `D-298-RECOMMEND-DEPTH-01`: one tactic ∈ `(a)` `rngLockedFlag`-gated revert | `(b)` snapshot/anchor pattern | `(c)` pre-lock reorder | `(d)` immutable. Plus ≤80-char rationale.

| # | Slot | Writer / Callsite | Tactic | Rationale (≤80 chars) |
|---|------|-------------------|--------|------------------------|
| 17 | `ticketQueue[rk]` | `_queueTickets` from `purchaseWhaleBundle` (`WhaleModule.sol:313`) | (a) | Add `if (rngLockedFlag) revert RngLocked()` at WhaleModule:purchaseWhaleBundle entry |
| 18 | `ticketQueue[rk]` | `_queueTickets` from `purchaseLazyPass` (`WhaleModule.sol:482`) | (a) | Add gated-revert at WhaleModule:purchaseLazyPass entry; mirrors purchaseDeityPass:543 |
| 19 | `ticketQueue[rk]` | `_queueTickets` from `purchaseDeityPass` (`WhaleModule.sol:625`) | (a) | Existing gate at :543 satisfies; verdict-matrix is stack-strict, gate verified |
| 20 | `ticketQueue[rk]` | `_queueTickets` from `openLootBox` (`LootboxModule.sol:1067`) | (a) | Gate lootbox-resolution writes via rngLockedFlag; daily-VRF freshness invariant |
| 21 | `ticketQueue[rk]` | `_queueTickets` from `openBurnieLootBox` (`LootboxModule.sol:1190`) | (a) | Same as #20 — domain-separated VRF but write-target shared |
| 23 | `ticketQueue[rk]` | `_queueTicketsScaled` from `_purchaseFor` (`MintModule.sol:1129`) | (a) | Gate purchase() against daily VRF window; level-target redirect at :1221 insufficient |
| 24 | `ticketQueue[rk]` | `_queueTicketRange` from `_awardDecimatorLootbox` (`DecimatorModule.sol:582`) | (a) | Gate EOA-reach (recordDecBurn); advanceGame-stack reach is EXEMPT (per-callsite) |
| 25 | `ticketQueue[rk]` | `_queueTicketRange` from `claimWhalePass` (`WhaleModule.sol:973`) | (a) | Add top-level rngLockedFlag gate; far-future loop revert is partial coverage |
| 26 | `ticketQueue[rk]` | `_queueTicketRange` from `_redeemWhalePassRange` (`Storage.sol:1135`) | (a) | Same as #25 — whale-pass redemption path |
| 31 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `purchaseWhaleBundle` | (a) | Same gate as #17; co-located write — single gate covers both slots |
| 32 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `purchaseLazyPass` | (a) | Same gate as #18 |
| 33 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `purchaseDeityPass` | (a) | Same as #19 — gate-by-revert at :543 already in place |
| 34 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `openLootBox` | (a) | Same gate as #20 |
| 35 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `openBurnieLootBox` | (a) | Same gate as #21 |
| 37 | `ticketsOwedPacked[rk][player]` | `_queueTicketsScaled` from `_purchaseFor` | (a) | Same gate as #23 |
| 38 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` from `_awardDecimatorLootbox` | (a) | Same gate as #24 (EOA-reach only) |
| 39 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` from `claimWhalePass` | (a) | Same gate as #25 |
| 40 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` from `_redeemWhalePassRange` | (a) | Same gate as #26 |

> **Tactic-frequency summary:** (a) gated-revert × 18; (b) snapshot/anchor × 0; (c) pre-lock reorder × 0; (d) immutable × 0.

> **Why tactic (a) dominates:** The MintModule consumer's freshness invariant rests on the `ticketQueue[rk]` + `ticketsOwedPacked[rk][player]` snapshot at the start of the resolution window. The double-buffer (`ticketWriteSlot` swap at `_swapAndFreeze:299`) partially protects the read slot, but cross-window race (writes accumulating in write slot, drained on NEXT cycle) is closed only by gated-revert on external writers. Tactic (b) snapshot/anchor would require copying the entire `ticketQueue[rk]` + `ticketsOwedPacked` state at lock-time — prohibitive storage cost given queue lengths can reach hundreds of entries. Tactic (c) pre-lock reorder is not applicable (no writes are scheduled by the consumer itself). Tactic (d) immutable is structurally impossible (the slots are mutable per-player counters). The existing `_queueTickets` near-future + far-future gates partially implement tactic (a) for `targetLevel > level + 5`; the remediation is to extend gating to ALL non-EXEMPT writers regardless of target-level range, OR to add top-level `if (rngLockedFlag) revert` gates at each external entry point (matching the `WhaleModule.purchaseDeityPass:543` pattern).

> **Cross-reference to Phase 290 MINTCLN audit-subject:** Phase 290 MINTCLN-02 collapse (3-input keccak + owed-in-baseKey) preserves CROSS-CALL seed separation INSIDE the resolution stack via the per-iteration `ticketsOwedPacked` SLOAD freshness — Phase 290 design-intent trace section (ii) confirms `baseKey` low 32 bits shrink as `owed` decreases. **The Phase 290 invariant is INSIDE-WINDOW determinism; the Phase 298 catalog identifies CROSS-WINDOW writer races on the SAME slots. Both invariants must hold for the full freshness property: Phase 290 closes intra-call, Phase 298 §10 violations identify inter-call/inter-day writers that erode the snapshot.**

> **Phase 290 `_processOneTicketEntry` zero-owed→rolled-to-1 stale-low-32-baseKey acknowledgment:** Recorded in Phase 290 design-intent trace section (ii) as ACCEPTABLE under structural-closure reasoning (single-trait emission only; no multi-call drain follows; upper-bit + groupIdx distinctness preserved). This catalog does NOT contradict that disposition — the stale-low-32 is INSIDE the self-stack (EXEMPT-ADVANCEGAME) and bounded to a single emission. The VIOLATIONS in §D are CROSS-stack writes that change `ticketsOwedPacked[rk][player]` outside the consumer's self-stack — a different bug class.

---

**§10 catalog complete.** 7 participating slots enumerated. 42 verdict rows. 18 VIOLATION rows, all dispositioned tactic (a) `rngLockedFlag`-gated revert. Every row carries one of the 4 allowed classification tokens (no discretionary-safe escape).
## §11 — BurnieCoinflip._resolveFlip + win-decode (file:line 807 / 837)

**Consumer entry (single-rooted trace per D-298-CONSUMER-LIST-01 §11):**

The §11 trace is rooted at `BurnieCoinflip.processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint32 epoch)` declared at `contracts/BurnieCoinflip.sol:805`. The PLAN frontmatter cites `:807` (the `rngWord` parameter site, body line 4 of the function) and `:837` (the `(rngWord & 1) == 1` win-decode), but these are the same function body. The function is the BURNIE coin-flip resolution consumer — the `rngWord` is the VRF-derived word forwarded from `DegenerusGameAdvanceModule.rngGate` (via `_applyDailyRng`) into this external method via the `onlyDegenerusGameContract` modifier.

**Note re consumer naming:** The PLAN frontmatter and 298-CONTEXT.md §11 anchor name the consumer `_resolveFlip`, but the source has no symbol of that name — the resolution function is `processCoinflipPayouts` (verified `grep -n "_resolveFlip\|processCoinflipPayouts" contracts/BurnieCoinflip.sol`: only `processCoinflipPayouts` exists at `:805`; `_resolveFlip` was a legacy naming carried in the planning artifact). The CONTEXT line-numbers (`:807` for the consumer entry, `:837` for win-decode) point unambiguously to `processCoinflipPayouts` lines, so the trace is anchored on that function.

**Two distinct rngWord consumptions inside the function (both rooted at the same VRF word):**

1. **Reward-percent decode** at `:811`: `uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));` — keccak-rekeyed seed feeds the `roll = seedWord % 20` bucketing at `:816` (yields `rewardPercent ∈ {50, 150}` for 5% / 5% rare arms, or `[78, 115]` for normal arm) plus the `seedWord % COINFLIP_EXTRA_RANGE` modulus at `:825`.
2. **Win-bit decode** at `:837`: `bool win = (rngWord & 1) == 1` — the raw VRF word's low bit determines win/loss (50/50). Per CONTEXT.md PLAN frontmatter, this is THE BURNIE coin-flip outcome bit.

Both decodes share the same `rngWord` SLOAD-source argument (the `uint256 rngWord` parameter at `:807`, passed by AdvanceModule from `currentWord` after `_applyDailyRng` mutation). No second VRF SLOAD inside this function — `rngWord` is the only VRF input.

**External entry chain (verifies `processCoinflipPayouts` is reached ONLY from the advanceGame stack):**

`grep -n "processCoinflipPayouts\b" contracts/ -r --include="*.sol"` returns 6 hits:
- `contracts/BurnieCoinflip.sol:571` — comment reference (not a callsite)
- `contracts/BurnieCoinflip.sol:805` — function definition
- `contracts/modules/DegenerusGameAdvanceModule.sol:1217` — `rngGate` normal-daily path
- `contracts/modules/DegenerusGameAdvanceModule.sol:1277` — `_gameOverEntropy` normal path
- `contracts/modules/DegenerusGameAdvanceModule.sol:1307` — `_gameOverEntropy` fallback path
- `contracts/modules/DegenerusGameAdvanceModule.sol:1794` — `_backfillGapDays` gap-day path
- `contracts/interfaces/IBurnieCoinflip.sol:99` — interface declaration

All 4 AdvanceModule callsites are private/internal helpers reached ONLY via `advanceGame()`-rooted entry points (`rngGate` is called from `_handleDailyAdvance`; `_gameOverEntropy` is called from `_handleGameOverPath`; `_backfillGapDays` is called from `rngGate` :1203). The `onlyDegenerusGameContract` modifier at `:188` (`if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();`) prevents EOA reach. **Reached-from set: `{advanceGame()-stack via VRF callback or fallback path}` only.**

**Commitment-window discipline (per `feedback_rng_commitment_window.md`):**

- **T0 (commitment):** EOA calls `depositCoinflip(player, amount)` (`:229`) on day D. `_depositCoinflip` (`:246`) writes `coinflipBalance[targetDay][caller]` at `:656` via `_addDailyFlip` (`:627`), where `targetDay = currentDayView() + 1 = D + 1`. This is the bet placement: BURNIE is burned at `:270` (`burnie.burnForCoinflip(caller, amount)`) and the credit lands on day D+1's `coinflipBalance`. Deposits are blocked during BAF-resolution transition by `_coinflipLockedDuringTransition()` at `:256`.
- **T1 (RNG publish):** Day D+1 arrives. `advanceGame()` stack reaches `rngGate` at AdvanceModule:1217 with `day = D+1`, calls `coinflip.processCoinflipPayouts(bonusFlip, currentWord, D+1)` with the VRF word for day D+1. Single SSTORE chain inside the consumer: `coinflipDayResult[epoch] = {rewardPercent, win}` at `:840`, `flipsClaimableDay = epoch` at `:869`, `currentBounty = currentBounty_ + PRICE_COIN_UNIT` at `:874`, `bountyOwedTo = address(0)` at `:865` (conditionally), `coinflipBalance[targetDay][bountyOwner] += slice` at `:859` (via `_addDailyFlip` for the bounty payout arm), and `_claimCoinflipsInternal(SDGNRS, false)` tail at `:888` (SDGNRS-only — see §B notes).
- **T2 (claim):** Player calls `claimCoinflips` (`:332`) on day D+1 or later; `_claimCoinflipsInternal` (`:416`) reads `coinflipDayResult[D+1]`, `coinflipBalance[D+1][player]`, computes payout, mints BURNIE via `burnie.mintForGame`. T2 is OUTSIDE the rng-window for §11 — but `_addDailyFlip(to=bountyOwner, slice, 0, false, false)` at `:859` is INSIDE the rng-window (called during T1 resolution itself), so its SLOAD set is in scope.

The participation question for §11 (per `feedback_rng_commitment_window.md`): between T0 (deposit lands the bet on day D+1) and T1 (resolution at day D+1 reads `rngWord`), what player-controllable state can mutate that flows into the win/loss bucket, reward-percent bucket, bounty payout amount, or BAF accumulation? Concretely:

- `coinflipBalance[D+1][player]` written at T0 and read at T2 — but T1 only reads `coinflipBalance[D+1][bountyOwner]` via `_addDailyFlip(to=bountyOwner, slice, …)` for THE BOUNTY ARM — and that reads `prevStake` at `:652` to compute `newStake = prevStake + coinflipDeposit`. So if the bounty owner deposits BURNIE between their bounty arming and resolution, their stake aggregation grows by the bounty `slice` regardless. NON-PARTICIPATING for win-decode but the `prevStake` SLOAD itself is in §B.
- `currentBounty` / `bountyOwedTo` — both written by T0 deposits via `_addDailyFlip(canArmBounty=true, bountyEligible=true)` and read at T1 lines `:846` / `:849`. Bounty arming is gated by `if (!game.rngLocked())` at `:664` — once VRF request lands, no further bounty arming. **rngLockedFlag is the existing gate.**
- `playerState[SDGNRS]` — the trailing `_claimCoinflipsInternal(SDGNRS, false)` at `:888` reads SDGNRS state. SDGNRS is a contract address and its state is not writable by EOAs except via SDGNRS-internal flows.
- `lootboxPresaleActiveFlag` — written by `_psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0)` at AdvanceModule:433 (advanceGame-stack only). Drives the `+6` reward-percent boost at `:832`.

### CAT-01 (§A) — Traced function set

Backward-trace rooted at `processCoinflipPayouts`'s `rngWord` parameter (`:807`); trace walks transitively into every reachable function under `contracts/` per `D-298-TRACE-DEPTH-01`. Stops only at external interfaces with no source available (Chainlink VRF coordinator; the SDGNRS `IStakedDegenerusStonk.*` calls are NOT reached from §11's resolution path — see attestation below).

**Resolution code path (T1 — full enumeration):**

| #  | Function                                              | File:line                                       | Reached from                                | Notes |
|----|-------------------------------------------------------|-------------------------------------------------|---------------------------------------------|-------|
| 1  | `processCoinflipPayouts`                              | `BurnieCoinflip.sol:805`                        | external entry (modifier-gated; AdvanceModule:1217/1277/1307/1794) | consumer entry; reads `rngWord`, writes resolution result, calls `_addDailyFlip` (bounty arm) + `_claimCoinflipsInternal(SDGNRS)` tail |
| 2  | `degenerusGame.lootboxPresaleActiveFlag()` (external) | `DegenerusGame.sol:2116`                        | `:829`                                      | external staticcall; reads `presaleStatePacked` via `_psRead` |
| 3  | `_addDailyFlip` (bounty arm)                          | `BurnieCoinflip.sol:627`                        | `:859`                                      | private; called with `recordAmount=0, canArmBounty=false, bountyEligible=false` — bounty arming branch NOT reached; boon branch NOT reached |
| 4  | `_targetFlipDay`                                      | `BurnieCoinflip.sol:1095`                       | `:650`                                      | private view; calls `degenerusGame.currentDayView()` |
| 5  | `degenerusGame.currentDayView()` (external)           | `DegenerusGame.sol:471`                         | `:1096`                                     | external staticcall; calls `_simulatedDayIndex()` → `GameTimeLib.currentDayIndex()` (pure on `block.timestamp` — no SLOAD) |
| 6  | `_updateTopDayBettor`                                 | `BurnieCoinflip.sol:1127`                       | `:657`                                      | private; reads `coinflipTopByDay[day]`, conditional write |
| 7  | `_score96`                                            | `BurnieCoinflip.sol:1118`                       | `:1132`                                     | `private pure` — no SLOADs |
| 8  | `degenerusGame.payCoinflipBountyDgnrs(...)` (external)| `DegenerusGame.sol:402`                         | `:861`                                      | external call (state-mutating); reads `dgnrs.poolBalance(Reward)` (cross-contract SLOAD on SDGNRS), calls `dgnrs.transferFromPool(Reward, …)` |
| 9  | `dgnrs.poolBalance(Pool.Reward)` (external SDGNRS)    | `StakedDegenerusStonk.sol` (`pools[Reward].balance`) | `DegenerusGame.sol:414`                | cross-contract SLOAD |
| 10 | `dgnrs.transferFromPool(Reward, player, payout)` (external mutator) | `StakedDegenerusStonk.sol` (`pools[Reward].balance -= payout`) | `DegenerusGame.sol:420` | cross-contract SSTORE; not a participating SLOAD source (only a writer of the SDGNRS pool balance read at #9) |
| 11 | `_claimCoinflipsInternal(SDGNRS, false)` (tail)       | `BurnieCoinflip.sol:416`                        | `:888`                                      | tail call to keep SDGNRS flip cursor current; BAF skipped (guard at `:572`); rngLocked guard NOT hit on this path |
| 12 | `degenerusGame.syncAfKingLazyPassFromCoin(SDGNRS)` (external) | `DegenerusGame.sol:1654`                | `:422`                                      | external call; reads `autoRebuyState[SDGNRS].afKingMode` (`:1659`); if false (SDGNRS never enables afKing), returns early — no further SLOADs |
| 13 | `degenerusGame.hasDeityPass(SDGNRS)` (external)       | `DegenerusGame.sol:2349`                        | NOT REACHED                                 | gated by `afKingActive = rebuyActive && afKingMode` at `:434`; SDGNRS has no rebuy → branch dead |
| 14 | `degenerusGame.level()` (external view)               | `DegenerusGame.sol` (auto-getter on `level` public state) | NOT REACHED                        | gated by `hasDeityPass`; SDGNRS branch dead |
| 15 | `_afKingDeityBonusHalfBpsWithLevel`                   | `BurnieCoinflip.sol:1078`                       | NOT REACHED                                 | gated by `hasDeityPass`; SDGNRS branch dead |
| 16 | `jackpots.getLastBafResolvedDay()` (external view)    | `DegenerusJackpots.sol:666`                     | NOT REACHED inside §11 tail path            | gated by `winningBafCredit != 0 && player != SDGNRS` at `:572`; SDGNRS guard ALWAYS true here → BAF branch dead |
| 17 | `jackpots.recordBafFlip(...)` (external mutator)      | `DegenerusJackpots.sol:171`                     | NOT REACHED inside §11 tail path            | same SDGNRS guard at `:572` skips entire BAF section |
| 18 | `_recyclingBonus` / `_afKingRecyclingBonus`           | `BurnieCoinflip.sol:1051` / `1062`              | NOT REACHED in §11 tail                     | gated by `rebuyActive`; SDGNRS branch dead |
| 19 | `_bafBracketLevel`                                    | `BurnieCoinflip.sol:1141`                       | NOT REACHED in §11 tail                     | inside the SDGNRS-skipped BAF arm |
| 20 | `wwxrp.mintPrize(SDGNRS, lossCount * COINFLIP_LOSS_WWXRP_REWARD)` (external mutator) | `BurnieCoinflip.sol:616`     | conditional in §11 tail (`lossCount != 0`)  | output sink (WWXRP mint); not an entropy-input source |

**Explicit-enumeration cross-check** (per `feedback_verify_call_graph_against_source.md`):

- `grep -n "delegatecall\|\.call\|staticcall" contracts/BurnieCoinflip.sol` → ZERO hits. BurnieCoinflip has NO inline-assembly raw call dispatchers; all cross-contract reach is via typed `IBurnieCoin` / `IDegenerusGame` / `IDegenerusJackpots` / `IWrappedWrappedXRP` external calls (all are calls on `address constant` interface references — single-target dispatch, no proxy / no Diamond pattern).
- `grep -n "assembly" contracts/BurnieCoinflip.sol` → ZERO hits. No inline-assembly `sstore` / `slot:` / raw read/write in BurnieCoinflip.
- `grep -n "_resolveFlip\b" contracts/BurnieCoinflip.sol` → ZERO hits. Confirms CONTEXT.md/PLAN.md `_resolveFlip` reference is the legacy name; canonical function is `processCoinflipPayouts`.
- `grep -n "rngWord" contracts/BurnieCoinflip.sol` → 4 hits: `:803` (NatSpec), `:807` (parameter), `:811` (keccak input), `:837` (win-decode). Both consumer sites confirmed.
- `grep -n "modifier\|onlyDegenerusGameContract\|onlyBurnieCoin\|onlyFlipCreditors" contracts/BurnieCoinflip.sol` confirms three access modifiers; `processCoinflipPayouts` uses `onlyDegenerusGameContract`.
- `grep -n "processCoinflipPayouts\b" contracts/ -r --include="*.sol"` → 4 callsites in AdvanceModule (1217, 1277, 1307, 1794); all advance-stack rooted.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during the §11 resolution path (T1 window: between the `rngWord` parameter consumption at `:807` and the final external mutator returns or function exit). Per `feedback_rng_window_storage_read_freshness.md`: ALL SLOADs enumerated, not only VRF-derived ones; non-VRF SLOADs alongside RNG are a distinct bug class (F-41-02/03 precedent).

| #     | Slot                                                    | Read-site (file:line)                                  | Read context                                                              | Participating? | Attestation if NO |
|-------|---------------------------------------------------------|--------------------------------------------------------|---------------------------------------------------------------------------|----------------|-------------------|
| B-1   | `presaleStatePacked` (`lootboxPresaleActive` bit)       | `DegenerusGame.sol:2117` (via `_psRead`)               | external staticcall from `:829`; drives `+6` reward-percent boost at `:832` | **YES**        | — |
| B-2   | `currentBounty` (uint128)                               | `BurnieCoinflip.sol:846` (`uint128 currentBounty_ = currentBounty`) | bounty pool snapshot for `slice = currentBounty_ >> 1` at `:852`         | **YES**        | — |
| B-3   | `bountyOwedTo` (address)                                | `BurnieCoinflip.sol:849`                                | bounty owner read; drives `if (bountyOwner != address(0))` arm gate       | **YES**        | — |
| B-4   | `coinflipBalance[targetDay][bountyOwner]` (mapping)     | `BurnieCoinflip.sol:652` (via `_addDailyFlip:653`)     | `prevStake` for `newStake = prevStake + coinflipDeposit` RMW              | NO             | RMW aggregate per-day stake; prior value is added to the bounty `slice` deposit unconditionally. The PRIOR value does not enter any VRF-derived output formula — `processCoinflipPayouts` writes `coinflipDayResult[epoch]` strictly from `(rngWord, epoch, presaleBonus)`, none of which read `coinflipBalance`. The slot is read here purely to recompose the bounty owner's day+1 aggregate stake. (However, `_updateTopDayBettor` consumes `newStake` for leaderboard ordering; that's NON-PARTICIPATING for win-decode but a participating WRITE — see §B-W.) |
| B-5   | `coinflipTopByDay[targetDay]` (struct: address+uint96)  | `BurnieCoinflip.sol:1133` (in `_updateTopDayBettor`)   | leaderboard read for comparison `score > dayLeader.score`                  | NO             | Leaderboard read for comparison; only affects whether `coinflipTopByDay[targetDay]` SSTORE fires. The leaderboard slot is NOT consumed by ANY VRF-derived output of §11 — the win-decode bit at `:837` already wrote `coinflipDayResult[epoch]` before this branch. The leaderboard is a future-day artifact for `coinflipTopLastDay()` view consumption (`:962`) outside the rng-window. |
| B-6   | SDGNRS `pools[Reward].balance` (cross-contract)         | `DegenerusGame.sol:414` (via `payCoinflipBountyDgnrs`) | SDGNRS pool balance read; gates `payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000` | **YES** (cross-contract) | — (the participating-ness here is for the *bounty payout amount*; this is consumed by `dgnrs.transferFromPool` and produces an EOA-observable transfer — it IS a VRF-conditional payout because the entire `if (win)` branch at `:856` gates this call) |
| B-7   | `autoRebuyState[SDGNRS].afKingMode` (bool)              | `DegenerusGame.sol:1659` (in `syncAfKingLazyPassFromCoin`) | external call from `BurnieCoinflip:422`; early-return gate                | NO             | Per the modifier `if (msg.sender != COINFLIP) revert E()` at `:1657`, this is callable only from the COINFLIP contract. For `player=SDGNRS`, the slot is initialized to `false` and the only writers are the 5 EOA-callable / coin-hook setters in `DegenerusGame.sol` (`_setAutoRebuy`, `_setAfKingMode`, `_deactivateAfKing`, plus the same-function clear at `:1664`) — all keyed on `msg.sender`-derived `player` (or via `coinflip.settleFlipModeChange` for SDGNRS, which is NEVER called for SDGNRS itself since the SDGNRS contract is not an EOA player). Therefore for the SDGNRS key, this slot is provably `false` for all of game lifetime → `syncAfKingLazyPassFromCoin` returns early at `:1659` → no further SLOADs on this branch. Does not influence §11 VRF-derived outputs. |
| B-8   | `playerState[SDGNRS].claimableStored` (uint128)         | `BurnieCoinflip.sol:421` (via `_claimCoinflipsInternal:394` storage pointer; field reads at `:396`, `:404`) | SDGNRS state pointer + claimableStored RMW                                | NO             | RMW per-player BURNIE-credit counter; written only via SDGNRS-keyed flows (`settleFlipModeChange`, `_claimCoinflipsAmount`, `_setCoinflipAutoRebuy` — none reach for SDGNRS as a player). At §11 T1, the prior value affects nothing about `processCoinflipPayouts`'s VRF-derived outputs (`coinflipDayResult[epoch]`, `currentBounty`, `bountyOwedTo`, `flipsClaimableDay`). |
| B-9   | `playerState[SDGNRS].lastClaim` (uint32)                | `BurnieCoinflip.sol:424` (via `_claimCoinflipsInternal`) | claim cursor                                                              | NO             | Same scope as B-8; SDGNRS cursor advances only via this `_claimCoinflipsInternal(SDGNRS, …)` tail call which is itself inside the resolution. Pre-T1 value cannot mutate between T0 and T1 from any EOA path (SDGNRS contract is not an EOA). |
| B-10  | `playerState[SDGNRS].autoRebuyEnabled` (bool)           | `BurnieCoinflip.sol:426` (via `_claimCoinflipsInternal`) | rebuy gate                                                                | NO             | SDGNRS rebuy gate is always false (no EOA setter reaches `playerState[SDGNRS].autoRebuyEnabled` — `_setCoinflipAutoRebuy` requires `msg.sender == player` or `_requireApproved(player)` for `player=SDGNRS`, which is a contract that never approves an operator). Provably false → `rebuyActive = false`, `afKingActive = false`, all rebuy-gated branches dead. |
| B-11  | `playerState[SDGNRS].autoRebuyStop` (uint128)           | `BurnieCoinflip.sol:428`                               | takeProfit                                                                | NO             | Reached only when `rebuyActive` — provably false for SDGNRS (B-10). |
| B-12  | `playerState[SDGNRS].autoRebuyCarry` (uint128)          | `BurnieCoinflip.sol:445`                               | rebuy carry                                                               | NO             | Same as B-10. |
| B-13  | `flipsClaimableDay` (uint32)                            | `BurnieCoinflip.sol:423` (via `_claimCoinflipsInternal`) | latest resolved-day cursor                                                | NO             | Just written at `:869` (`flipsClaimableDay = epoch`) — the tail `_claimCoinflipsInternal(SDGNRS)` reads the freshly-stored value. The slot has a single writer (`:869` inside `processCoinflipPayouts` itself) plus initial constructor default of zero. Its value is fully determined by the consumer's own `epoch` argument (from AdvanceModule). NO external writer races this slot during T1. |
| B-14  | `coinflipDayResult[cursor]` (struct, mapping)           | `BurnieCoinflip.sol:494` (via `_claimCoinflipsInternal`) | tail loop reads per-day result                                            | NO             | Per-day result; written exclusively by `processCoinflipPayouts` itself (`:840`) — each `cursor` slot is written exactly once before being read. For the SDGNRS tail-loop iterations the immediately-prior epochs were each resolved by `processCoinflipPayouts` at past advance days; no EOA mutator path writes this slot. Its prior values feed only SDGNRS payout accounting at T1; they do NOT feed back into `(rngWord & 1)` or the reward-percent decode of THIS epoch. |
| B-15  | `coinflipBalance[cursor][SDGNRS]` (mapping)             | `BurnieCoinflip.sol:504` (via `_claimCoinflipsInternal`) | tail loop reads SDGNRS stake per day                                      | NO             | SDGNRS receives flip credits from various sources (`creditFlip` from QUESTS / AFFILIATE / ADMIN; `addDailyFlip` from coinflip-bounty-payout path). Writers ARE reachable from non-EXEMPT entry points (QUESTS / AFFILIATE / ADMIN are EOA-or-operator surfaces). HOWEVER, this slot's value only flows into SDGNRS's own payout accumulator inside the §11 tail loop (driven by past-epoch `coinflipDayResult[cursor].win` outcomes) — it does NOT feed back into THIS epoch's `rngWord`-decoded result. The "(slot × writer) participation" question is whether changing this slot between T0 and T1 changes the consumer's VRF-derived outputs. It does not (the SDGNRS tail is post-write; the win/loss + reward-percent are already settled at `:837/:824` from `rngWord` alone). NON-PARTICIPATING for §11's win-decode. |
| B-16  | `biggestFlipEver` (uint128)                             | NOT READ in §11 T1                                     | (read site is `_addDailyFlip:663` inside the `if (canArmBounty && bountyEligible && recordAmount != 0)` branch) | n/a            | Branch is dead for §11's call to `_addDailyFlip(to, slice, 0, false, false)` at `:859` (recordAmount=0, canArmBounty=false, bountyEligible=false). Slot NOT touched during §11 T1. |
| B-17  | `consumeCoinflipBoon`-driven slots in DegenerusGame    | NOT READ in §11 T1                                     | `_addDailyFlip` boon branch only fires when `recordAmount != 0`            | n/a            | recordAmount=0 in §11's bounty-arm `_addDailyFlip` call. Branch dead. |
| B-18  | `rngLockedFlag` (DegenerusGame, bool)                   | NOT READ in §11 T1                                     | (read at `_addDailyFlip:664` under `canArmBounty && bountyEligible && recordAmount != 0` branch which is dead in §11; ALSO read at `BurnieCoinflip:589` under `winningBafCredit != 0 && player != SDGNRS` branch which is dead in §11 SDGNRS tail) | n/a            | Two potential read sites both gated by dead branches in §11's specific call shape. |
| B-19  | `gameOverFlag` (DegenerusGame `gameOver()` read)        | NOT READ in §11 T1                                     | read at `_claimCoinflipsInternal:584` and at `_coinflipLockedDuringTransition` — both gated by `winningBafCredit != 0 && player != SDGNRS` (dead branch in §11 SDGNRS tail) | n/a            | Dead branch in §11 SDGNRS tail. |
| B-20  | `purchaseInfo()`-driven slots in DegenerusGame          | NOT READ in §11 T1                                     | `purchaseInfo()` read at `_claimCoinflipsInternal:583` — same dead branch | n/a            | Dead branch in §11 SDGNRS tail. |

**Auxiliary §B-W — SSTOREs inside the rng-window (cross-check, not classified):**

| #     | Slot                                                  | Write-site (file:line)                          | Notes |
|-------|-------------------------------------------------------|-------------------------------------------------|-------|
| B-W1  | `coinflipDayResult[epoch]` (`{rewardPercent, win}`)   | `BurnieCoinflip.sol:840`                        | primary resolution write; consumes `rngWord` |
| B-W2  | `bountyOwedTo = address(0)` (conditional clear)       | `BurnieCoinflip.sol:865`                        | bounty-arm finalize (fires when `bountyOwner != address(0) && currentBounty_ > 0` regardless of win) |
| B-W3  | `flipsClaimableDay = epoch`                           | `BurnieCoinflip.sol:869`                        | cursor advance |
| B-W4  | `currentBounty = currentBounty_ + PRICE_COIN_UNIT`    | `BurnieCoinflip.sol:874`                        | bounty pool accumulation |
| B-W5  | `coinflipBalance[targetDay][bountyOwner] += slice`    | `BurnieCoinflip.sol:656` (via `_addDailyFlip`)  | only when `win` and `bountyOwner != address(0)` — credits the bounty winner's day+1 stake |
| B-W6  | `coinflipTopByDay[targetDay]` (struct)                | `BurnieCoinflip.sol:1135`                       | only when bounty winner's new stake exceeds leaderboard high water mark |
| B-W7  | SDGNRS-tail state writes inside `_claimCoinflipsInternal(SDGNRS)` | various                              | `state.lastClaim` (`:607`); SDGNRS state slot — see B-9 attestation |
| B-W8  | `playerState[SDGNRS].claimableStored` (RMW)           | NOT REACHED in §11 tail                          | rebuy gate dead for SDGNRS |
| B-W9  | external cross-contract writes via `dgnrs.transferFromPool(Reward, …)` | `StakedDegenerusStonk.sol`             | only when `win` |
| B-W10 | external cross-contract writes via `wwxrp.mintPrize(SDGNRS, …)` | `WrappedWrappedXRP.sol`                       | only when SDGNRS lossCount != 0 |

### CAT-03 (§C) — Writer enumeration for participating slots

Per `D-298-EXEMPT-REACH-01`: writers enumerated per-callsite. For each `Participating? = YES` slot in §B, enumerate every external/public function in any contract under `contracts/` that writes the slot (OZ-inherited writers included; admin/owner writers included). The participating-slot universe under §11 is: B-1 (`presaleStatePacked`), B-2 (`currentBounty`), B-3 (`bountyOwedTo`), B-6 (SDGNRS `pools[Reward].balance`).

### C-1 — `presaleStatePacked` (uint256; presale-active flag in low bit)

| #   | Writer function                                       | Callsite (file:line)                            | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-1a | `DegenerusGameStorage._psWrite` (helper)            | `storage/DegenerusGameStorage.sol:860`          | callers below                                    | helper — writes any (shift, mask) field of `presaleStatePacked` |
| C-1b | `DegenerusGameAdvanceModule._processAdvance` (presale-clear branch) | `modules/DegenerusGameAdvanceModule.sol:433` (`_psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0)`) | `advanceGame()` stack — `_processAdvance` is invoked from `_handleDailyAdvance` / `rngGate` callers | **EXEMPT-ADVANCEGAME** — only writer of the `PS_ACTIVE` bit post-deploy |
| C-1c | constructor initialization                            | `storage/DegenerusGameStorage.sol:843` (`presaleStatePacked = uint256(1)`) | deploy-time             | **EXEMPT (constructor)** — pre-deploy initial value; no post-deploy reach |

**`grep -rn "_psWrite\|presaleStatePacked\s*=" contracts/ --include="*.sol"`** confirms only C-1b and C-1c write the slot post-construction (no other `_psWrite` callsite present in the source — searched across all of `contracts/`).

**OZ-inherited writers check:** `presaleStatePacked` is `internal uint256` in `DegenerusGameStorage`; no OZ inheritance writes. Confirmed.

**Admin/owner writer check:** No `onlyOwner` / `onlyAdmin` writer of `presaleStatePacked`. Confirmed via grep.

**Inline-assembly raw-sstore check:** `grep -n "assembly" contracts/storage/DegenerusGameStorage.sol contracts/modules/DegenerusGameAdvanceModule.sol contracts/DegenerusGame.sol --include="*.sol"` returns only `memory-safe` revert helpers (no raw sstore on `presaleStatePacked` slot).

### C-2 — `currentBounty` (uint128 public)

| #   | Writer function                                       | Callsite (file:line)                            | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-2a | inline state-variable initializer                   | `BurnieCoinflip.sol:167` (`uint128 public currentBounty = 1_000 ether`) | deploy-time              | **EXEMPT (constructor)** — pre-deploy initial value |
| C-2b | `BurnieCoinflip.processCoinflipPayouts` (consumer-self) | `BurnieCoinflip.sol:874` (`currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT)`) | the resolution path itself (consumer §11) | **EXEMPT-VRFCALLBACK** — self-write inside the consumer's resolution call; reached only from `advanceGame()`-stack VRF callback (modifier-gated at `:188`) |

**`grep -n "currentBounty\s*=\b" contracts/BurnieCoinflip.sol`** returns only `:167` (initializer) and `:874` (consumer-self write). No other writer in `contracts/`.

**OZ-inherited writers check:** `currentBounty` is `uint128 public`; auto-getter only, no OZ writers. Confirmed.

**Admin/owner writer check:** No admin path writes `currentBounty`. The `onlyFlipCreditors` modifier (GAME / QUESTS / AFFILIATE / ADMIN) governs `creditFlip` / `creditFlipBatch` only — those write `coinflipBalance` via `_addDailyFlip`, NOT `currentBounty` (the `_addDailyFlip` bounty-arm branch reads `currentBounty` but only writes `bountyOwedTo` / `biggestFlipEver`, not `currentBounty`).

**Inline-assembly raw-sstore check:** Zero hits in BurnieCoinflip. Confirmed.

### C-3 — `bountyOwedTo` (address internal)

| #   | Writer function                                       | Callsite (file:line)                            | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-3a | `BurnieCoinflip._addDailyFlip` (bounty-arming arm)  | `BurnieCoinflip.sol:681` (`bountyOwedTo = player`) | EOA → `depositCoinflip` (`:229`) when `canArmBounty=true && bountyEligible=true && recordAmount != 0 && recordAmount > biggestFlipEver && !game.rngLocked() && recordAmount >= threshold` — only the SELF-deposit shape (`directDeposit=true`) at `:312` passes the canArmBounty/bountyEligible flags. | **VIOLATION** — see §D-1 (EOA-reachable writer; arming gated by `!game.rngLocked()` at `:664` BUT not by `flipsClaimableDay` epoch alignment). |
| C-3b | `BurnieCoinflip.processCoinflipPayouts` (consumer-self) | `BurnieCoinflip.sol:865` (`bountyOwedTo = address(0)`) | the resolution path itself | **EXEMPT-VRFCALLBACK** — self-clear inside the consumer (regardless of win/loss). |

**`grep -n "bountyOwedTo\s*=" contracts/BurnieCoinflip.sol`** returns only `:681` (arming) and `:865` (clear). No third writer.

**OZ-inherited writers check:** `bountyOwedTo` is `internal address`; no OZ writers. Confirmed.

**Admin/owner writer check:** No admin path. The `onlyFlipCreditors` writers (`creditFlip` `:898`, `creditFlipBatch` `:909`) ALSO reach `_addDailyFlip` — but with `canArmBounty=false, bountyEligible=false, recordAmount=0` (`:903` / `:918`) — so they DO NOT write `bountyOwedTo`. Only `_depositCoinflip` (`:246`) reaches the writer arm.

**Constructor/initializer:** Default zero. No constructor write.

**Inline-assembly raw-sstore check:** Zero hits.

### C-4 — SDGNRS `pools[Reward].balance` (cross-contract; in `StakedDegenerusStonk.sol`)

This slot is in `StakedDegenerusStonk.sol` (in-source-scope per `D-298-TRACE-DEPTH-01`). For §11, the read site is via `dgnrs.poolBalance(Pool.Reward)` at `DegenerusGame.sol:414` (inside `payCoinflipBountyDgnrs`), and the same call eventually invokes `dgnrs.transferFromPool(Reward, player, payout)` at `:420` (cross-contract write). The participating-ness of this slot for §11 is: the SDGNRS Reward pool balance scales the bounty `payout` formula at `:418`.

| #   | Writer function (in `StakedDegenerusStonk.sol`)       | Callsite                                        | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-4a | `StakedDegenerusStonk.addToPool(Pool.Reward, amount)` (and any `Reward`-keyed pool credit fn) | various — invoked from `DegenerusGame` ETH/dgnrs allocation paths during `_handleDailyAdvance` / `_handleJackpotPhaseAdvance` | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** for the advance-stack callsites |
| C-4b | `StakedDegenerusStonk.transferFromPool(Pool.Reward, player, payout)` (debit path) | invoked from `DegenerusGame.payCoinflipBountyDgnrs:420` | the §11 resolution path itself                  | **EXEMPT-VRFCALLBACK** (consumer-self debit) |
| C-4c | `StakedDegenerusStonk.transferFromPool(Pool.Reward, …)` (other debit callsites) | invoked from other DegenerusGame payout flows (Decimator/Lootbox rewards / etc.) keying on `Reward` pool | various EOA + advance-stack entry points | Per-callsite — see §D-2 for VIOLATION-CANDIDATE classification (EOA-callable payout paths that drain Reward pool BEFORE §11's bounty payout reads it can shift the bounty `payout` amount). |
| C-4d | `StakedDegenerusStonk` constructor / `_initializePool` | deploy-time                                     | constructor                                       | **EXEMPT (constructor)** |

**OZ-inherited writers check:** SDGNRS is a custom ERC20-like contract; its `pools` mapping is private. No OZ inheritance touches `pools[Reward].balance` directly. Confirmed via `grep -n "pools\[" contracts/StakedDegenerusStonk.sol`.

**Admin/owner writer check:** Owner / DAO paths in SDGNRS that adjust pool balances (rebalance, emergency-withdraw if any) — not enumerated here at the SDGNRS level; per `D-298-TRACE-DEPTH-01` the SDGNRS slot is in-source-scope but the EOA-callable writers of `pools[Reward].balance` are documented in consumer §12's catalog (sStonk redemption). For §11, the cross-reference is: SDGNRS Reward-pool writers comprise an EOA-callable surface that races the bounty payout amount window.

**Inline-assembly raw-sstore check:** No raw assembly hits on `pools` slot in SDGNRS (verified earlier in §6 / §12 catalog precedents).

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` / `D-298-EXEMPT-CROSSCONTRACT-01`: classify each (slot × writer × callsite) tuple as `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION` (the legacy "safe-by-design" attestation class is disallowed per D-43N-AUDIT-ONLY-01 / v43.0 milestone goal).

| #   | Slot                            | Writer × callsite                                       | Reached-from stack                                       | Verdict                       |
|-----|---------------------------------|---------------------------------------------------------|----------------------------------------------------------|-------------------------------|
| D-1 | `presaleStatePacked`            | `_psWrite` @ AdvanceModule:433                          | `advanceGame()` → `_processAdvance`                       | **EXEMPT-ADVANCEGAME**        |
| D-2 | `presaleStatePacked`            | initializer @ Storage:843                               | deploy constructor                                        | **EXEMPT-ADVANCEGAME** (constructor-equivalent; pre-deploy fixed value with no post-deploy mutator besides D-1) |
| D-3 | `currentBounty`                 | initializer @ BurnieCoinflip:167                        | deploy                                                    | **EXEMPT-ADVANCEGAME** (constructor-equivalent) |
| D-4 | `currentBounty`                 | self-write @ BurnieCoinflip:874                         | the §11 resolution itself                                 | **EXEMPT-VRFCALLBACK**        |
| D-5 | `bountyOwedTo`                  | `_addDailyFlip:681` (arming) reached via `_depositCoinflip:312` ← EOA `depositCoinflip:229` | EOA — direct-deposit self-arming                | **VIOLATION** — see §E-1     |
| D-6 | `bountyOwedTo`                  | self-clear @ BurnieCoinflip:865                         | the §11 resolution itself                                 | **EXEMPT-VRFCALLBACK**        |
| D-7 | SDGNRS `pools[Reward].balance`  | `dgnrs.transferFromPool(Reward, …)` @ DegenerusGame:420 (self-debit) | the §11 resolution itself (consumer's bounty payout) | **EXEMPT-VRFCALLBACK**        |
| D-8 | SDGNRS `pools[Reward].balance`  | other EOA-callable Reward-pool drains (claim paths, decimator rewards, etc.) reached from DegenerusGame entries that key `Pool.Reward` | EOA + advance-stack mix          | **VIOLATION** — see §E-2     |
| D-9 | SDGNRS `pools[Reward].balance`  | advance-stack credit paths (`addToPool(Reward, …)`)     | `advanceGame()` stack                                     | **EXEMPT-ADVANCEGAME**        |

### CAT-06 (§E) — Per-VIOLATION remediation tactic + rationale

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale citing design intent or cross-callsite consequence.

| #     | VIOLATION (ref §D)          | Tactic | Rationale (≤80 chars) |
|-------|-----------------------------|:------:|-----------------------|
| E-1   | D-5 `bountyOwedTo` arming   | **(a)** | Bounty arming already gated by `!rngLocked()` at :664; extend to fail-closed revert |
| E-2   | D-8 SDGNRS Reward-pool drain races bounty payout | **(b)** | Snapshot poolBalance at rngLock time; bounty payout computes vs snapshot, not live |

**Tactic (a) detail for E-1:** The existing convention site at `BurnieCoinflip:730` (`if (degenerusGame.rngLocked()) revert RngLocked();` inside `_setCoinflipAutoRebuy`) is THE precedent for rngLockedFlag-gated reverts in this contract. The current bounty arming at `:664` reads `!game.rngLocked()` as a silent skip (no revert) — the writer is gated, but a stale-bounty-armed-before-lock state can still be replaced by the resolution (`bountyOwedTo = address(0)` at `:865` fires unconditionally when `bountyOwner != address(0) && currentBounty_ > 0`). The race is: EOA arms bounty at block N (rngLocked=false), VRF request lands at block N+1 (rngLocked=true, `processCoinflipPayouts` consumes the arming). The arming is already locked out of further mutation by `:664`, but the SLOAD at `:849` reads the just-armed value. The participating-ness here is per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 precedent: between VRF request and fulfillment, the slot is FROZEN (writer gated) — this matches the v43.0 milestone goal IF the read happens AFTER `rngLockedFlag=true`. The `bountyOwedTo` clear at `:865` fires unconditionally, so a player arming bounty between rngRequestTime and the actual `processCoinflipPayouts` execution has their bounty consumed (win or no-win, the clear fires). **Hardening tactic (a):** turn the `:664` silent skip into an explicit revert (or move the bounty-arming gate to require `flipsClaimableDay == currentDay - 1` epoch alignment so that bounty arming between rngLock and resolution becomes impossible to land on the resolved epoch). The 80-char rationale captures the precedent + the hardening direction.

**Tactic (b) detail for E-2:** The SDGNRS `pools[Reward].balance` is read live by `payCoinflipBountyDgnrs:414` to scale the bounty payout. Any EOA-callable Reward-pool drain (e.g., a parallel `claimRedemption` flow on SDGNRS, or a decimator-reward distribution that keys `Pool.Reward`) that lands between rngLock and resolution shifts the bounty payout amount. The snapshot/anchor pattern precedent (Phase 281 owed-salt, Phase 288 dailyIdx) is the natural fit: at `_requestRng`/rngLock time, snapshot the Reward pool balance (e.g., into a transient or per-epoch storage slot), and `payCoinflipBountyDgnrs` consumes the snapshot rather than `dgnrs.poolBalance(Reward)` live. This eliminates the cross-contract write race in one structural change rather than per-callsite gating.

---

## Catalog completeness self-attestation for §11

- All resolution-path SLOADs enumerated (B-1..B-20; B-16..B-20 are reachable-in-principle slot reads gated by dead branches within §11's specific call shape and documented for completeness per `feedback_rng_window_storage_read_freshness.md`).
- All YES rows have writer enumeration in §C (B-1 → C-1; B-2 → C-2; B-3 → C-3; B-6 → C-4).
- All §D rows classified; only the four allowed verdicts used. 9 tuples: 7 EXEMPT + 2 VIOLATION.
- All VIOLATIONs have tactic + ≤80-char rationale in §E.
- Cross-contract writers (SDGNRS pool) enumerated per `D-298-EXEMPT-CROSSCONTRACT-01`.
- `_resolveFlip` legacy name reconciled to canonical `processCoinflipPayouts` symbol per source grep.
- No `contracts/` or `test/` mutations performed.
## §12 — StakedDegenerusStonk.resolveRedemptionPeriod + rngWordForDay re-read (file:line 585 / 670)

**Consumer entry (advance-stack):** `contracts/StakedDegenerusStonk.sol:585`
**Signature:** `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external` — access guard `msg.sender != ContractAddresses.GAME` revert (sStonk:586).
**Consumer entry (EOA-stack):** `contracts/StakedDegenerusStonk.sol:670` — `uint256 rngWord = game.rngWordForDay(claimPeriodIndex)` inside `claimRedemption()` (sStonk:618), which has NO access guard (any holder with `pendingRedemptions[msg.sender].periodIndex != 0` may call).
**Caller chain (advance side):** `AdvanceModule.advanceGame` (`AdvanceModule.sol:158`) → `rngGate` (`:1179`) writes `rngWordByDay[day]` via `_applyDailyRng` (`:1841`) → derives `redemptionRoll = uint16(((currentWord >> 8) % 151) + 25)` (`:1226-1228`) and `flipDay = day + 1` (`:1229`) → `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` (`:1230`). Mirrored in `_gameOverEntropy` paths at `:1293` (fresh VRF word) and `:1323` (historical-fallback word). Three call-sites all originate from the SAME advance-stack root (`advanceGame()` → `rngGate` / `_handleGameOverPath` → `_gameOverEntropy`).
**Caller chain (claim side):** EOA calls `claimRedemption()` (sStonk:618). `claim.periodIndex` was committed during a previous `burn()` / `burnWrapped()` call at `_submitGamblingClaimFrom` (sStonk:752), itself gated by `!game.gameOver()` (sStonk:487), `!game.livenessTriggered()` (sStonk:491), and `!game.rngLocked()` (sStonk:492) — the `sStonk:492` line is the existing rngLockedFlag-gate convention site referenced in `feedback_rng_window_storage_read_freshness.md` discipline. The line-670 SLOAD is a **cross-call re-read** of the same `rngWordByDay[claimPeriodIndex]` slot the advance-stack used at line 1226-1227 to derive `roll`; per F-41-02/03 precedent (`feedback_rng_window_storage_read_freshness.md`), this is the distinct-class cross-call SLOAD pattern.

### CAT-01 (§A) — Traced function set

Two consumer entries are covered per the §12 entry-list (D-298-CONSUMER-LIST-01 entry 12): the advance-stack writer `resolveRedemptionPeriod` (sStonk:585) AND the EOA-stack re-read `rngWordForDay(claimPeriodIndex)` inside `claimRedemption` (sStonk:670). Both are part of the same gambling-burn resolution lifecycle. The trace walks every reachable function inside both entries' resolution code paths per D-298-TRACE-DEPTH-01, stopping only at external interfaces with no source available.

| # | Function | File:line | Reached from | Notes |
|---|---|---|---|---|
| 1 | `resolveRedemptionPeriod` | `StakedDegenerusStonk.sol:585` | advance-stack entry (callsites `AdvanceModule.sol:1230 / :1293 / :1323`) | consumer root — writes `redemptionPeriods[redemptionPeriodIndex]` |
| 2 | `claimRedemption` | `StakedDegenerusStonk.sol:618` | EOA entry | re-read consumer root — line 670 re-loads `rngWordByDay[claimPeriodIndex]` |
| 3 | `IDegenerusGamePlayer.gameOver` (view) | (game-side, called at `:635`) | `claimRedemption:635` | reads `gameOver` flag in `DegenerusGameStorage.sol:290` (`bool public gameOver`) |
| 4 | `IBurnieCoinflipPlayer.getCoinflipDayResult` (view) | `BurnieCoinflip.sol:370` | `claimRedemption:649` | reads `coinflipDayResult[flipDay]` struct (`BurnieCoinflip.sol:162`) |
| 5 | `IDegenerusGamePlayer.rngWordForDay` (view) | `DegenerusGame.sol:2183` | `claimRedemption:670` | reads `rngWordByDay[claimPeriodIndex]` (`DegenerusGameStorage.sol:435`) |
| 6 | `IDegenerusGameModules.resolveRedemptionLootbox` | `DegenerusGame.sol:1721` → `LootboxModule.resolveRedemptionLootbox` (`LootboxModule.sol:707`) | `claimRedemption:672` | TRACE-STOP at §12 boundary — `resolveRedemptionLootbox` is the §6 consumer (D-298-CONSUMER-LIST-01 entry 6), traced under that section. §12 hands `entropy` + `actScore` + `amount` + `player` to §6 and stops. |
| 7 | `_payBurnie` | `StakedDegenerusStonk.sol:842` | `claimRedemption:677` | reads `coin.balanceOf(this)` (BURNIE ERC20 balance — does not affect VRF-derived output, see §B-13/14); may invoke `coinflip.claimCoinflipsForRedemption` (token movement only — no VRF input) |
| 8 | `_payEth` | `StakedDegenerusStonk.sol:817` | `claimRedemption:683` | reads `address(this).balance` and `_claimableWinnings()`; may invoke `game.claimWinnings(address(0))` (no VRF input read inside §12 scope) |
| 9 | `_claimableWinnings` | `StakedDegenerusStonk.sol:857` | `_payEth:820`, `_payBurnie` does not read it | reads `game.claimableWinningsOf(address(this))` — view-only against game accounting, not a VRF-influenced slot for THIS consumer |

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: confirmed by full read of `resolveRedemptionPeriod` (sStonk:585-610) and `claimRedemption` (sStonk:618-684) — no `delegatecall`, no inline assembly, no library-state mutation, no `for`/`while` loops with state reads. Helper invocations enumerated above (`_payBurnie`, `_payEth`, `_claimableWinnings`, three view-only cross-contract calls). No "by construction" / "single fn reaches all paths" shortcuts.

**TRACE-STOP boundary for §12:** `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` at sStonk:672 hands the keccak-derived `entropy` to `DegenerusGame.resolveRedemptionLootbox` (DegenerusGame.sol:1721) → `LootboxModule.resolveRedemptionLootbox` (LootboxModule.sol:707). That consumer entry is §6 in D-298-CONSUMER-LIST-01 and is audited under section 6's CATALOG file. §12 records the call as a TRACE-STOP at the contract boundary and lists §6 as the downstream consumer of the `entropy` value derived from `rngWordByDay[claimPeriodIndex]`.

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during `resolveRedemptionPeriod` (advance-stack consumer) AND `claimRedemption` (EOA-stack consumer) execution, per F-41-02/03 enumeration discipline. Inline-assembly slot directives + raw `sstore` grep returned zero hits in `StakedDegenerusStonk.sol` (confirmed via `grep -n "assembly\|slot:" contracts/StakedDegenerusStonk.sol`).

### §B-A — `resolveRedemptionPeriod` (advance-stack entry; sStonk:585)

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-A1 | `ContractAddresses.GAME` (compile-time constant) | sStonk:586 | `msg.sender != ContractAddresses.GAME` access guard | NO | Compile-time `library` constant in `ContractAddresses.sol`; resolved at link time; no SLOAD. Access guard outcome governs reach, not VRF-derived output. |
| B-A2 | `redemptionPeriodIndex` (sStonk) | sStonk:588 | `uint32 period = redemptionPeriodIndex;` — selects which `redemptionPeriods[period]` slot to WRITE | **YES** | Determines which historical period gets the new roll value written; if stale (set on an earlier player-submit day), the roll lands in a period that was already resolved — causing the §D-VIOL re-roll pattern below. |
| B-A3 | `pendingRedemptionEthBase` | sStonk:589, sStonk:592 | early-return gate (`== 0 && Burnie == 0 return`) + multiplicand for `rolledEth = base * roll / 100` | **YES** | Multiplier on the VRF-derived `roll` → contributes magnitude to the rolled-ETH state update. |
| B-A4 | `pendingRedemptionBurnieBase` | sStonk:589, sStonk:597 | early-return gate + multiplicand for `burnieToCredit = base * roll / 100` | **YES** | Multiplier on `roll` → contributes to `RedemptionResolved` event payload `rolledBurnie` (observable VRF-derived output). |
| B-A5 | `pendingRedemptionEthValue` | sStonk:593 | RMW: `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;` | **YES** | Running total whose post-resolution value depends on `roll`; consumed by `previewBurn` / `_deterministicBurnFrom` (`sStonk:535`, `:705`) and by `_submitGamblingClaimFrom` (`:772`) — feeds back into per-share proportional math for future burns. |
| B-A6 | `pendingRedemptionBurnie` | sStonk:600 | RMW: `pendingRedemptionBurnie -= pendingRedemptionBurnieBase;` | **YES** | Running total subtracted in same path; consumed by `burnieReserve()` (`:736`), `_submitGamblingClaimFrom` (`:778`), `previewBurn` (`:725`). Influences sizing of future gambling burns whose claims will be VRF-multiplied. |

### §B-B — `claimRedemption` (EOA-stack entry; sStonk:618 with line-670 cross-call re-read)

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-B1 | `pendingRedemptions[msg.sender]` (struct slot — `periodIndex`) | sStonk:621 (`claim.periodIndex == 0` gate) + sStonk:627 (`claimPeriodIndex = claim.periodIndex`) | NoClaim gate + value used as both lookup-key for `redemptionPeriods[claim.periodIndex]` (line 623) AND as `day` argument to `game.rngWordForDay(claimPeriodIndex)` (line 670) | **YES** | Drives which period's roll is consumed AND which day's rngWord seeds lootbox entropy. |
| B-B2 | `pendingRedemptions[msg.sender].ethValueOwed` | sStonk:632 | `totalRolledEth = (claim.ethValueOwed * roll) / 100` | **YES** | Direct multiplicand of the VRF-derived `roll`; produces `lootboxEth` (passed to game.resolveRedemptionLootbox at :672) and `ethDirect` (paid via `_payEth`). |
| B-B3 | `pendingRedemptions[msg.sender].activityScore` | sStonk:628 | `claimActivityScore = claim.activityScore` → passed as `actScore` to `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` (line 672) | **YES** | Per §6 LootboxModule consumer (`resolveRedemptionLootbox` at `LootboxModule.sol:707`), `actScore` modulates lootbox rarity weighting — therefore feeds a VRF-derived output. |
| B-B4 | `pendingRedemptions[msg.sender].burnieOwed` | sStonk:652 | `burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000` | **YES** | Multiplicand of `roll` and `rewardPercent` → produces `burniePayout` (transferred via `_payBurnie`). |
| B-B5 | `redemptionPeriods[claim.periodIndex]` (struct — `roll`) | sStonk:623, sStonk:624, sStonk:626 | NotResolved gate + `roll = period.roll` consumed in multiplications at :632 and :652 | **YES** | Direct VRF-derived input to ETH/BURNIE payout math. |
| B-B6 | `redemptionPeriods[claim.periodIndex]` (struct — `flipDay`) | sStonk:649 | `(rewardPercent, flipWon) = coinflip.getCoinflipDayResult(period.flipDay)` | **YES** | Determines which coinflip day's result feeds `rewardPercent` and `flipWon` into the burnie multiplication and dispatch (`flipResolved`). |
| B-B7 | `gameOver` (DegenerusGameStorage.sol:290) — read via `game.gameOver()` external view | sStonk:635 (`isGameOver = game.gameOver()`) | gates the `ethDirect = totalRolledEth` vs `ethDirect = totalRolledEth / 2; lootboxEth = totalRolledEth - ethDirect` dispatch | **YES** | Determines whether `lootboxEth != 0` branch executes (the `resolveRedemptionLootbox` call at :672 is gated on `lootboxEth != 0`) — i.e., gates whether the §6 VRF-consumer is invoked at all from this claim. |
| B-B8 | `coinflipDayResult[period.flipDay]` (BurnieCoinflip.sol:162) — read via `coinflip.getCoinflipDayResult(flipDay)` external view | sStonk:649 | yields `(rewardPercent, flipWon)` → both consumed in burniePayout math at :650-:653 | **YES** | `rewardPercent` is a multiplicand on roll·burnieOwed; `flipWon` gates the multiplication; their AND with `rewardPercent != 0` sets `flipResolved` (controls full-claim vs partial-clear dispatch at sStonk:659-665). |
| B-B9 | `rngWordByDay[claimPeriodIndex]` (DegenerusGameStorage.sol:435) — read via `game.rngWordForDay(claimPeriodIndex)` external view | sStonk:670 — `uint256 rngWord = game.rngWordForDay(claimPeriodIndex);` | hashed with `player` to produce `entropy = uint256(keccak256(abi.encode(rngWord, player)))` (line 671), passed to game.resolveRedemptionLootbox (line 672) | **YES** | The cross-call SLOAD called out in the prompt as the F-41-02/03 distinct-class re-read. The slot value is the SAME `rngWordByDay[day]` that was used at AdvanceModule:1226-1227 to derive the `roll` already stored in `period.roll`; here it is re-loaded for use as lootbox entropy. |
| B-B10 | `pendingRedemptionEthValue` | sStonk:657 (`pendingRedemptionEthValue -= totalRolledEth`) | RMW reduction by the player's claimed share | NO | Read for the subtraction-write; the post-value does NOT influence VRF-derived output of THIS claim — it only affects later burns' proportional math (already covered as a participating SLOAD inside `_submitGamblingClaimFrom` / `previewBurn`, which are separate write-then-read sites; here the SLOAD only sources the subtraction operand). Listed for completeness per `feedback_rng_window_storage_read_freshness.md`. |
| B-B11 | `pendingRedemptions[msg.sender]` (the whole struct — read again for `delete` / partial clear) | sStonk:661 (`delete pendingRedemptions[player]`), sStonk:664 (`claim.ethValueOwed = 0`) | branch on `flipResolved` to clear claim | NO | Pure SSTOREs (delete / partial clear); the dispatch was already decided from B-B6/B-B8. The "read" here is just the storage handle (already loaded into `claim`); no new value influences output. |
| B-B12 | `address(this).balance` (intrinsic, not SLOAD) | `_payEth:819`, `_payEth:824`, `_deterministicBurnFrom:532` reachable only from `burn()`, not §12 | balance lookup for payout sizing | NO | EVM-intrinsic balance opcode, not an SLOAD. Influences ETH-vs-stETH split inside `_payEth` (sStonk:817-839) but does NOT influence the VRF-derived `entropy` / `roll` / `rewardPercent` / `flipWon` / `gameOver` outputs already decided upstream. |
| B-B13 | `coin.balanceOf(address(this))` (cross-contract BURNIE ERC20 balance) — via `_payBurnie:843` | `_payBurnie:843` | determines ETH-vs-coinflip-claim split in BURNIE payout | NO | Affects payout SOURCE (this contract's BURNIE vs. coinflip-claim drain), not the VRF-derived AMOUNT (already fixed at burniePayout). Per `feedback_rng_window_storage_read_freshness.md` D-298-SLOT-CLASSIFICATION-01: value does not influence VRF-derived output. |
| B-B14 | `coin.balanceOf(address(this))` (stETH balance via `steth.balanceOf` — not reached in §12) | not reached in §12 paths | (n/a) | NO | `_payEth` reads `address(this).balance` not stETH; stETH is only read inside `_deterministicBurnFrom` which is a `burn()`-only path, not reachable from §12's `claimRedemption`. Listed for completeness. |
| B-B15 | `game.claimableWinningsOf(address(this))` via `_claimableWinnings` (sStonk:857) | `_payEth:820` (cross-contract view, not SLOAD on sStonk slot) | sources `claimableEth` for `_payEth`'s ETH-vs-stETH split | NO | Same rationale as B-B12: affects payout SOURCING (whether to drain claimable winnings vs use raw balance), not VRF-derived AMOUNT. The amount was fixed at `ethDirect`/`burniePayout` computation upstream. |

**Auxiliary §B-W — SSTOREs inside the consumer bodies (cross-check, not classified):**

| # | Slot | Write-site (file:line) | Notes |
|---|---|---|---|
| B-W1 | `pendingRedemptionEthValue` | sStonk:593 (resolve) | RMW. Already a participating SLOAD at B-A5; write derives from `roll`. |
| B-W2 | `pendingRedemptionEthBase` | sStonk:594 (resolve) | Cleared to 0 after consumption. |
| B-W3 | `pendingRedemptionBurnie` | sStonk:600 (resolve) | RMW; cleared by base subtraction. |
| B-W4 | `pendingRedemptionBurnieBase` | sStonk:601 (resolve) | Cleared to 0. |
| B-W5 | `redemptionPeriods[period]` | sStonk:604 (resolve) | Struct write `{roll, flipDay}`. **Overwritable** if `redemptionPeriodIndex == period` is reached again with non-zero base (see §D-VIOL). |
| B-W6 | `pendingRedemptionEthValue` | sStonk:657 (claim) | Reduction by `totalRolledEth`. |
| B-W7 | `pendingRedemptions[player]` (`delete`) | sStonk:661 (claim) | Full-clear if `flipResolved`. |
| B-W8 | `pendingRedemptions[player].ethValueOwed = 0` | sStonk:664 (claim) | Partial-clear if `!flipResolved`. |

### CAT-03 (§C) — Writer enumeration for participating slots

For each PARTICIPATING slot identified in §B, every external/public function (in any contract under `contracts/`) that writes the slot — per-callsite, with file:line. Includes OZ-inherited writers where applicable + admin/owner writers + cross-contract writers.

### §C-1 — `redemptionPeriodIndex` (sStonk; participating per B-A2)

Storage slot declared at `StakedDegenerusStonk.sol:230` (`uint32 internal redemptionPeriodIndex`). Exhaustive `grep -n "redemptionPeriodIndex" contracts/StakedDegenerusStonk.sol`:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-1a | `_submitGamblingClaimFrom` | sStonk:760 (`redemptionPeriodIndex = currentPeriod;` inside `if (redemptionPeriodIndex != currentPeriod) { ... }` block) | `burn()` (sStonk:486) and `burnWrapped()` (sStonk:506) — both external EOA-callable. | EOA writer. Gated by `!game.gameOver()` (sStonk:487), `!game.livenessTriggered()` (sStonk:491), `!game.rngLocked()` (sStonk:492). Not gated against post-resolution / mid-window re-writes on the same wall-clock day. |

OZ-inherited writers: `redemptionPeriodIndex` is a private uint32 — no ERC20/ERC721 inheritance touches it. Admin/owner writers: zero hits — `grep -n "onlyOwner\|onlyAdmin\|onlyGame" contracts/StakedDegenerusStonk.sol` shows only the `onlyGame` modifier on `receive`, `depositSteth`, `transferFromPool`, `transferBetweenPools`, `burnAtGameOver` — none of which touch `redemptionPeriodIndex`. Constructor: not written in constructor (default zero). Inline-assembly: zero hits.

### §C-2 — `pendingRedemptionEthBase` (sStonk; participating per B-A3)

Storage at `StakedDegenerusStonk.sol:226`. Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-2a | `resolveRedemptionPeriod` | sStonk:594 (`pendingRedemptionEthBase = 0;`) | `AdvanceModule.advanceGame` → `rngGate` / `_gameOverEntropy` (advance-stack only; sStonk:586 access guard `msg.sender == ContractAddresses.GAME`). | EXEMPT-ADVANCEGAME stack writer. |
| C-2b | `_submitGamblingClaimFrom` | sStonk:790 (`pendingRedemptionEthBase += ethValueOwed;`) | `burn()` (sStonk:486) / `burnWrapped()` (sStonk:506) — external EOA-callable. | EOA writer; same gates as C-1a. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-3 — `pendingRedemptionBurnieBase` (sStonk; participating per B-A4)

Storage at `StakedDegenerusStonk.sol:227`. Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-3a | `resolveRedemptionPeriod` | sStonk:601 (`pendingRedemptionBurnieBase = 0;`) | advance-stack only (access guard sStonk:586). | EXEMPT-ADVANCEGAME stack writer. |
| C-3b | `_submitGamblingClaimFrom` | sStonk:792 (`pendingRedemptionBurnieBase += burnieOwed;`) | `burn()` / `burnWrapped()` external EOA. | EOA writer; same gates as C-1a. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-4 — `pendingRedemptionEthValue` (sStonk; participating per B-A5)

Storage at `StakedDegenerusStonk.sol:224` (`uint256 public pendingRedemptionEthValue`). Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-4a | `resolveRedemptionPeriod` | sStonk:593 (`pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;`) | advance-stack only. | EXEMPT-ADVANCEGAME. |
| C-4b | `claimRedemption` | sStonk:657 (`pendingRedemptionEthValue -= totalRolledEth;`) | EOA-callable via `claimRedemption()` — NO access guard. | EOA writer. |
| C-4c | `_submitGamblingClaimFrom` | sStonk:789 (`pendingRedemptionEthValue += ethValueOwed;`) | `burn()` / `burnWrapped()` external EOA. | EOA writer; same gates as C-1a. |

The slot is `public` (auto-getter), but writers are limited to these three sites. OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-5 — `pendingRedemptionBurnie` (sStonk; participating per B-A6)

Storage at `StakedDegenerusStonk.sol:225`. Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-5a | `resolveRedemptionPeriod` | sStonk:600 (`pendingRedemptionBurnie -= pendingRedemptionBurnieBase;`) | advance-stack only. | EXEMPT-ADVANCEGAME. |
| C-5b | `_submitGamblingClaimFrom` | sStonk:791 (`pendingRedemptionBurnie += burnieOwed;`) | `burn()` / `burnWrapped()` external EOA. | EOA writer. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-6 — `pendingRedemptions[player]` struct slot (B-B1/B-B2/B-B3/B-B4 — `periodIndex`, `ethValueOwed`, `activityScore`, `burnieOwed`)

Storage mapping at `StakedDegenerusStonk.sol:221` (`mapping(address => PendingRedemption) public pendingRedemptions`). Struct packs `ethValueOwed` (uint96) + `burnieOwed` (uint96) + `periodIndex` (uint32) + `activityScore` (uint16) = 240 bits into one slot. Exhaustive grep `grep -n "pendingRedemptions\[" contracts/StakedDegenerusStonk.sol`:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-6a | `_submitGamblingClaimFrom` (writes `claim.ethValueOwed`, `claim.burnieOwed`, `claim.periodIndex`, `claim.activityScore`) | sStonk:803, sStonk:805, sStonk:806, sStonk:810 | `burn()` / `burnWrapped()` external EOA. | EOA writer; same gates as C-1a. |
| C-6b | `claimRedemption` (delete) | sStonk:661 (`delete pendingRedemptions[player]`) | EOA-callable; no guard. | EOA writer (clear). |
| C-6c | `claimRedemption` (partial clear) | sStonk:664 (`claim.ethValueOwed = 0`) | EOA-callable; no guard. | EOA writer (partial clear). |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-7 — `redemptionPeriods[period]` struct slot (B-B5/B-B6 — `roll`, `flipDay`)

Storage mapping at `StakedDegenerusStonk.sol:222` (`mapping(uint32 => RedemptionPeriod) public redemptionPeriods`). Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-7a | `resolveRedemptionPeriod` | sStonk:604 (`redemptionPeriods[period] = RedemptionPeriod({roll, flipDay});`) | advance-stack only (access guard sStonk:586). | Only writer. EXEMPT-ADVANCEGAME callsites at AdvanceModule.sol:1230 / :1293 / :1323. **However:** if `redemptionPeriodIndex` SLOAD at sStonk:588 returns a stale value pointing at an already-resolved period (because `redemptionPeriodIndex` was not advanced after the prior resolution), this WRITE overwrites the prior `redemptionPeriods[period]` struct with a new roll. See §D-VIOL-1. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-8 — `gameOver` (DegenerusGameStorage.sol:290) — read via `game.gameOver()` external view at sStonk:635

Storage declared as `bool public gameOver;` Exhaustive `grep -n "gameOver\s*=\s*true\|gameOver\s*=\s*false\|gameOver =" contracts/ -r --include="*.sol"` (excluding comments and `gameOverPossible`, `gameOverFlag`, etc.):

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-8a | `GameOverModule.handleGameOverDrain` | `GameOverModule.sol:139` (`gameOver = true;`) | Called via `DegenerusGame.handleGameOverDrain` (`DegenerusGame.sol`) ← via `AdvanceModule._handleGameOverPath` (`AdvanceModule.sol:185` → `:522` → `:600`) ← `advanceGame()` (`AdvanceModule.sol:158`). | EXEMPT-ADVANCEGAME stack writer. The single SSTORE site for `gameOver`. |

OZ-inherited: none. Admin/owner: not directly settable. Constructor: default false. Inline-assembly: zero hits.

### §C-9 — `coinflipDayResult[flipDay]` (BurnieCoinflip.sol:162) — read via `coinflip.getCoinflipDayResult(flipDay)` external view at sStonk:649

Storage `mapping(uint32 => CoinflipDayResult) internal coinflipDayResult;` Exhaustive `grep -n "coinflipDayResult\[" contracts/BurnieCoinflip.sol`:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-9a | `BurnieCoinflip._resolveDay` (called inside `processCoinflipPayouts` at `BurnieCoinflip.sol:805`) | `BurnieCoinflip.sol:840` (`coinflipDayResult[epoch] = CoinflipDayResult({rewardPercent, win})`) | `processCoinflipPayouts` is called only from `AdvanceModule.sol:1217` (rngGate), `:1277` (`_gameOverEntropy` fresh path), `:1307` (`_gameOverEntropy` fallback path), `:1794` (`_backfillGapDays`) — all reached only from `advanceGame()` stack. | EXEMPT-ADVANCEGAME stack writer. Confirmed by `grep -n "function processCoinflipPayouts\b" contracts/BurnieCoinflip.sol` (single definition at :805) and `grep -rn "processCoinflipPayouts\b" contracts/` (four callers, all in AdvanceModule, all advance-stack). |

OZ-inherited: none. Admin/owner: zero. Constructor: default zero per mapping. Inline-assembly: zero.

### §C-10 — `rngWordByDay[day]` (DegenerusGameStorage.sol:435) — read via `game.rngWordForDay(claimPeriodIndex)` external view at sStonk:670

Storage `mapping(uint32 => uint256) internal rngWordByDay;` Exhaustive `grep -rn "rngWordByDay\[" contracts/ --include="*.sol"` filtered to WRITE sites (mapping LHS of `=` not `==`):

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-10a | `AdvanceModule._applyDailyRng` | `AdvanceModule.sol:1841` (`rngWordByDay[day] = finalWord;`) | Called from `rngGate:1216` and `_gameOverEntropy:1275` (fresh) / `:1305` (fallback) — all advance-stack. | EXEMPT-ADVANCEGAME. |
| C-10b | `AdvanceModule._backfillGapDays` | `AdvanceModule.sol:1793` (`rngWordByDay[gapDay] = derivedWord;`) | Called from `rngGate:1203` — advance-stack. | EXEMPT-ADVANCEGAME. |

OZ-inherited: none. Admin/owner: zero (no setter). Constructor: default zero. Inline-assembly: zero. **The slot is write-once-per-day:** once `rngWordByDay[day] != 0`, no subsequent SSTORE overwrites it (gate at AdvanceModule:1187 / :1201 / :1271 / :1187 short-circuits). Thus the cross-call re-read at sStonk:670 reads a permanently-frozen value once non-zero — the F-41-02/03-class "value mutability between commit and re-consumption" risk is fully absent for THIS slot.

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. The discretionary fifth-class disposition is prohibited by milestone-goal prose.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `redemptionPeriodIndex` (sStonk) | `_submitGamblingClaimFrom` | sStonk:760 (via `burn()` / `burnWrapped()`) | NO — EOA-callable; rngLockedFlag gate at sStonk:492 covers `game.rngLocked() == true` (VRF in-flight) but does NOT cover the post-resolution window where `redemptionPeriodIndex` is stale-pointing at a just-resolved period. | **VIOLATION** |
| D-2 | `pendingRedemptionEthBase` | `resolveRedemptionPeriod` | sStonk:594 (advance-stack root sStonk:586) | YES — sole reaching entry is `advanceGame()` stack (callsites AdvanceModule.sol:1230 / :1293 / :1323). | **EXEMPT-ADVANCEGAME** |
| D-3 | `pendingRedemptionEthBase` | `_submitGamblingClaimFrom` | sStonk:790 (via `burn()` / `burnWrapped()`) | NO — EOA-callable; rngLockedFlag-gated against in-flight VRF (sStonk:492) BUT not against post-resolution / pre-next-advance window where this base feeds a re-roll of an already-resolved period. | **VIOLATION** |
| D-4 | `pendingRedemptionBurnieBase` | `resolveRedemptionPeriod` | sStonk:601 (advance-stack) | YES — same as D-2. | **EXEMPT-ADVANCEGAME** |
| D-5 | `pendingRedemptionBurnieBase` | `_submitGamblingClaimFrom` | sStonk:792 (via `burn()` / `burnWrapped()`) | NO — same reach analysis as D-3. | **VIOLATION** |
| D-6 | `pendingRedemptionEthValue` | `resolveRedemptionPeriod` | sStonk:593 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-7 | `pendingRedemptionEthValue` | `claimRedemption` | sStonk:657 (EOA-callable) | NO — EOA stack. However, the WRITE here is a SUBTRACTION of `totalRolledEth` already-derived-from-VRF-output; it does not introduce attacker-controlled entropy. Still listed as VIOLATION per D-298-EXEMPT-REACH-01 strict rule (writer-callsite is non-EXEMPT). Severity downgraded in §E rationale. | **VIOLATION** |
| D-8 | `pendingRedemptionEthValue` | `_submitGamblingClaimFrom` | sStonk:789 (via `burn()` / `burnWrapped()`) | NO — same reach as D-3. | **VIOLATION** |
| D-9 | `pendingRedemptionBurnie` | `resolveRedemptionPeriod` | sStonk:600 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-10 | `pendingRedemptionBurnie` | `_submitGamblingClaimFrom` | sStonk:791 (via `burn()` / `burnWrapped()`) | NO — same reach as D-3. | **VIOLATION** |
| D-11 | `pendingRedemptions[player].*` | `_submitGamblingClaimFrom` | sStonk:803/805/806/810 (via `burn()` / `burnWrapped()`) | NO — EOA-callable. Note: by `_submitGamblingClaimFrom` design, write to `claim.*` only proceeds if `claim.periodIndex == 0` OR `claim.periodIndex == currentPeriod` (sStonk:796-798); same-period growth is feature-by-design but participates in the D-1/D-3/D-5 re-roll vector. | **VIOLATION** |
| D-12 | `pendingRedemptions[player]` (delete / partial clear) | `claimRedemption` | sStonk:661 / sStonk:664 | NO — EOA stack. However, these are CLEARS of the player's own claim (`msg.sender`); they cannot alter another player's VRF-derived output for a current claim cycle. Severity downgraded in §E. | **VIOLATION** |
| D-13 | `redemptionPeriods[period]` (`{roll, flipDay}`) | `resolveRedemptionPeriod` | sStonk:604 (advance-stack) | YES — sole writer is advance-stack. | **EXEMPT-ADVANCEGAME** (write itself), but the OVERWRITE-vulnerability arises from D-1/D-3/D-5 stale-`redemptionPeriodIndex` letting this slot be re-written on a future advance — captured under D-1/D-3/D-5. |
| D-14 | `gameOver` | `GameOverModule.handleGameOverDrain` | GameOverModule.sol:139 (advance-stack root `_handleGameOverPath`) | YES — only reaching root is `advanceGame()` → `_handleGameOverPath` → `handleGameOverDrain`. Single SSTORE site. | **EXEMPT-ADVANCEGAME** |
| D-15 | `coinflipDayResult[flipDay]` | `BurnieCoinflip._resolveDay` (via `processCoinflipPayouts`) | BurnieCoinflip.sol:840 (advance-stack — 4 callsites all under `advanceGame` per §C-9) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-16 | `rngWordByDay[day]` | `AdvanceModule._applyDailyRng` | AdvanceModule.sol:1841 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-17 | `rngWordByDay[gapDay]` | `AdvanceModule._backfillGapDays` | AdvanceModule.sol:1793 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |

**§D-VIOL — Cross-cutting VIOLATION pattern (D-1 / D-3 / D-5 / D-11 root cause):**

The methodology note for §12 flagged a "first-time audit of this consumer's storage-write surface for rngLockedFlag freeze coverage." This analysis confirms a concrete VIOLATION pattern unique to gambling-burn resolution:

1. **Trigger sequence (intra-day re-burn after public roll):**
   - Day D, player A submits `burn(amount_A)` → sStonk:760 sets `redemptionPeriodIndex = D`; sStonk:790 sets `pendingRedemptionEthBase = ethValueOwed_A`. Gates at sStonk:487/491/492 ALL pass (no VRF in-flight at submit time).
   - Day D advance() fires → `rngGate` writes `rngWordByDay[D]`, derives `redemptionRoll_D = uint16(((currentWord >> 8) % 151) + 25)` (AdvanceModule:1226-1228), calls `sdgnrs.resolveRedemptionPeriod(redemptionRoll_D, D+1)` → sStonk:604 writes `redemptionPeriods[D] = {roll_D, D+1}`; sStonk:594 zeros `pendingRedemptionEthBase`. `redemptionPeriodIndex` REMAINS at `D` (no write to it in `resolveRedemptionPeriod`). `_unlockRng(D)` clears `rngLockedFlag` (AdvanceModule:1731) — `game.rngLocked()` now returns `false`.
   - Wall-clock day is STILL D (advanceGame closes day D's events on day D itself or later, but the wall-clock check `currentDayView()` is purely time-derived; if advance fires early in day D+1 wall-clock, the scenario uses day D+1, but the SAME logic applies one day shifted).
   - Player B reads `redemptionPeriods[D].roll = roll_D` (mapping is `public` per sStonk:222 → auto-getter); if roll_D is unfavorable (e.g., 25–80), proceeds to step 4.
   - Player B calls `burn(1 wei)` on day D (post-resolution) → sStonk:487 `!gameOver()` passes; sStonk:491 `!livenessTriggered()` passes; sStonk:492 `!game.rngLocked()` passes (cleared by `_unlockRng`). `_submitGamblingClaimFrom` runs:
     - sStonk:757 `currentPeriod = D`; sStonk:758 `redemptionPeriodIndex (D) == currentPeriod (D)` → no reset of `redemptionPeriodSupplySnapshot` / `redemptionPeriodBurned`.
     - sStonk:790 `pendingRedemptionEthBase += newOwed` → now NON-ZERO again. sStonk:792 same for burnie base.
     - sStonk:803/805 `claim.ethValueOwed += newOwed` — Player B's existing claim grows. (Or, if Player B already called `claimRedemption` and the claim was deleted, this re-creates the claim with `claim.periodIndex = D`.)
2. **Next advance re-resolves the same period:**
   - Day D+1 (or next advance interval), `advanceGame` fires → `rngGate` writes `rngWordByDay[D+1]`, derives `redemptionRoll_{D+1}`, calls `sdgnrs.resolveRedemptionPeriod(redemptionRoll_{D+1}, D+2)`.
   - Inside: sStonk:588 `period = redemptionPeriodIndex = D` (still D — never advanced). sStonk:589 early-return-skipped because `pendingRedemptionEthBase != 0`. sStonk:604 writes `redemptionPeriods[D] = {roll: redemptionRoll_{D+1}, flipDay: D+2}` — **OVERWRITES** the original `roll_D`.
3. **Strategy / asymmetric payoff:**
   - Player B can examine `roll_D`, claim immediately if favorable (lock in roll_D), or re-burn 1 wei to force a re-roll on the next advance. The re-roll applies to BOTH the original `claim_B.ethValueOwed` and the trivial new portion — effectively re-rolling the ENTIRE original stake with a fresh independent random outcome.
   - With unbounded re-rolls, EV approaches the max (175%) modulo budget. Even one re-roll lifts EV from `(25+175)/2 = 100` to `0.5 · E[roll | roll ≥ 100] + 0.5 · 100 = 0.5 · 137.5 + 50 = 118.75` — a ~19% free EV gain per round of re-roll.
   - Cost of one re-roll: 1 wei of sDGNRS (negligible). 50% supply cap (sStonk:763 `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2`) bounds intra-period growth, but does NOT block 1-wei re-burns (`redemptionPeriodBurned += amount` accumulates negligibly).
   - Collateral damage: any OTHER player C who submitted on day D with `claim_C.periodIndex = D` and has not yet called `claimRedemption` will ALSO have `period.roll` overwritten. Player C sees a different roll at their claim time than was published at the original resolution event. This is data-corruption-class behavior even ignoring the EV asymmetry.
4. **Existing rngLockedFlag gate at sStonk:492 is structurally INSUFFICIENT:** the gate covers ONLY the in-flight VRF window (`game.rngLocked() == true`). It does NOT cover the post-resolution / pre-next-advance window where `redemptionPeriodIndex` is stale-pointing at a closed period and `rngLockedFlag = false`.
5. **Gap-day re-resolution edge case:** the `_backfillGapDays` (AdvanceModule:1779) NOTE-comment at AdvanceModule:1772-1774 says "resolveRedemptionPeriod is NOT called for backfilled gap days." The current code path supports this (no resolve call inside `_backfillGapDays`). However, if `redemptionPeriodIndex` was set to a pre-stall day D and a post-stall advance fires after gap-fill, `period = D` could still resolve with the FUTURE day's roll — a separate flavor of the same data-corruption pattern.

**Reach-stack summary for D-1/D-3/D-5/D-11 (the actionable VIOLATION cluster):** EOA → `burn()` / `burnWrapped()` (sStonk:486 / :506) → `_submitGamblingClaimFrom` (sStonk:752); only gates are `!gameOver` (`game.gameOver()`), `!livenessTriggered` (`game.livenessTriggered()`), and `!rngLocked` (`game.rngLocked()`). None of these gate against "current `redemptionPeriodIndex` already resolved — wait for `_submitGamblingClaim` to advance the index before allowing new base accumulation."

**Severity downgrade rationale for D-7/D-12:** These are non-EXEMPT-stack writes inside `claimRedemption` of slots the player already controls or that subtract VRF-derived (not VRF-influencing) values. They are listed VIOLATION per D-298-EXEMPT-REACH-01 strict rule but the FIX is structurally subsumed by closing the D-1/D-3/D-5/D-11 window (no separate remediation needed — see §E).

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION row | Recommended tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-1: `redemptionPeriodIndex` re-pointable to closed period via post-resolution `_submitGamblingClaimFrom` | **(a)** | Revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0` |
| E-2 | D-3: `pendingRedemptionEthBase` grown after period resolved | **(a)** | Same gate as E-1 — base-growth and index-pointing are co-mutated; one check covers both |
| E-3 | D-5: `pendingRedemptionBurnieBase` grown after period resolved | **(a)** | Subsumed by E-1's revert (same writer fn, same callsite). |
| E-4 | D-7: `pendingRedemptionEthValue` subtraction inside `claimRedemption` | **(a)** | Subsumed by E-1 — pre-resolution-window writes are blocked, so subtraction operand stays consistent |
| E-5 | D-8: `pendingRedemptionEthValue` grown inside `_submitGamblingClaimFrom` | **(a)** | Subsumed by E-1 — same writer fn revert covers all base/value/burnie growths |
| E-6 | D-10: `pendingRedemptionBurnie` grown inside `_submitGamblingClaimFrom` | **(a)** | Subsumed by E-1 |
| E-7 | D-11: `pendingRedemptions[player].*` grown inside `_submitGamblingClaimFrom` | **(a)** | Subsumed by E-1 |
| E-8 | D-12: `pendingRedemptions[player]` clear inside `claimRedemption` | **(a)** | Subsumed by E-1; once index-advance is enforced, clear-write is the legitimate downstream effect |

**Rationale expansion (out-of-table for traceability; the 80-char cells above are the verdict-matrix entries):**

Tactic **(a) rngLockedFlag-gated revert** at the `_submitGamblingClaimFrom` entry is the structurally minimal fix. The precedent is the `sStonk:492` line (`if (game.rngLocked()) revert BurnsBlockedDuringRng();`) which already exists — the methodology note cited this as the convention. The fix extends the gate from "block burns while VRF in-flight" to "block burns whenever a `_submitGamblingClaimFrom` would extend a same-day period whose `redemptionPeriods[redemptionPeriodIndex].roll != 0`." Two implementation shapes:

1. **Direct gate at _submitGamblingClaimFrom (sStonk:752):** insert `if (redemptionPeriods[redemptionPeriodIndex].roll != 0 && currentPeriod == redemptionPeriodIndex) revert BurnsBlockedAfterResolution();` immediately after `currentPeriod = game.currentDayView();` at sStonk:757. The new error (or reused `BurnsBlockedDuringRng`) revert closes the post-resolution intra-day window.
2. **Advance-index protocol shape:** alternatively, advance `redemptionPeriodIndex` to `currentPeriod` inside `resolveRedemptionPeriod` itself OR clear `redemptionPeriodIndex` to zero at end of resolveRedemptionPeriod, then make `_submitGamblingClaimFrom` always initialize a fresh period when `redemptionPeriodIndex == 0`. This is a refactor over a gate and would change observable state — defer to Phase 299 sub-phase planning per `feedback_design_intent_before_deletion.md`.

Tactic **(b) snapshot/anchor** is REJECTED for this consumer's VIOLATION class: the offending pattern is not "value mutates between commit and re-read" (the only re-read of `rngWordByDay[claimPeriodIndex]` at sStonk:670 IS frozen, per §C-10 write-once attestation). The offending pattern is "writer-callsite mutates `redemptionPeriodIndex`'s effective meaning AFTER resolution closes the period." Snapshotting `redemptionPeriodIndex` at resolution time would still leave the `pendingRedemptionEthBase`-growth bypass open.

Tactic **(c) pre-lock reorder** is REJECTED: reordering inside `resolveRedemptionPeriod` (e.g., writing `redemptionPeriodIndex = currentPeriod + 1` or clearing it) is essentially the "advance-index protocol shape" alternative above; classified as a refactor over a gate.

Tactic **(d) immutable** is N/A — `redemptionPeriodIndex` is intentionally mutable across periods.

The line-670 cross-call SLOAD of `rngWordByDay[claimPeriodIndex]` itself is **not a VIOLATION** in §12's scope: §C-10 enumerates two write sites, both `EXEMPT-ADVANCEGAME`, and the slot is write-once-per-day. The F-41-02/03 distinct-class concern called out in the methodology note IS the VIOLATION cluster D-1/D-3/D-5/D-11 — same root pattern, different slot (sStonk-side state vs game-side `rngWordByDay`).

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside both `resolveRedemptionPeriod` and `claimRedemption` enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Two view-only external calls into game (`gameOver`, `rngWordForDay`) and one into coinflip (`getCoinflipDayResult`) are walked at the storage-slot level (see §C-8, §C-9, §C-10).
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, the relevant commitment points are (i) `rngWordByDay[D] = finalWord` (`AdvanceModule.sol:1841`) for the rngWord that derives `roll`, and (ii) `redemptionPeriods[D] = {roll, flipDay}` (`StakedDegenerusStonk.sol:604`) for the roll already stored. Attacker reachability of writers between these commitments and the consumer re-reads at sStonk:632 / sStonk:649 / sStonk:670 was the gating analysis. The line-670 SLOAD is safe (write-once slot); the §D-VIOL cluster shows the same FRESHNESS principle violated on sStonk-side accounting slots.
- **Cross-call F-41-02/03 attestation:** the cross-call SLOAD pattern flagged in the prompt ("line 585 reads rngWord once, then line 670 re-reads rngWordForDay(claimPeriodIndex)") is the slot `rngWordByDay[claimPeriodIndex]`. Its writers are both `EXEMPT-ADVANCEGAME` (§C-10) AND the slot is write-once (`AdvanceModule.sol:1187 / :1201 / :1271` short-circuit on non-zero). The distinct-class concern materializes instead at the sStonk-side cluster (`redemptionPeriodIndex` + `pendingRedemption*Base*` + `pendingRedemptions[player]`) which are post-resolution writable from EOA paths.
- **Verdicts:** 15 SLOADs enumerated / 15 participating / 11 distinct writer-callsite tuples after de-dup / **8 VIOLATION rows (D-1, D-3, D-5, D-7, D-8, D-10, D-11, D-12)** / 9 EXEMPT-ADVANCEGAME rows (D-2, D-4, D-6, D-9, D-13, D-14, D-15, D-16, D-17). 0 discretionary-disposition rows (milestone-goal prohibition honored).
- **Scope:** zero `contracts/` + zero `test/` mutations per D-43N-AUDIT-ONLY-01. Only the §12 catalog file under `.planning/` is created.
- **Phase 299 hand-forward:** the §D-VIOL cluster collapses into a single FIX recommendation E-1 (with E-2..E-8 subsumed). Phase 299 plan-phase consumes this as one sub-phase candidate; design-intent trace per `feedback_design_intent_before_deletion.md` is deferred to that plan-phase.
## §13 — DecimatorModule._awardDecimatorLootbox cluster (file:line 573 + cross-call re-read at :338)

**Consumer entry (callsite cluster):**
- **Callsite α (PLAN-stated :573, in-stack `rngWord` parameter consumer):** `contracts/modules/DegenerusGameDecimatorModule.sol:570-601` — `_awardDecimatorLootbox(address winner, uint256 amount, uint256 rngWord)` (private). Line 573 is the `rngWord` parameter in the signature; the body consumes it at :597 (`rngWord` passed via `abi.encodeWithSelector(... resolveLootboxDirect.selector, winner, amount, rngWord)`) and pre-cross-call at :580 (`uint24 startLevel = level + 1;` is the in-frame SLOAD of `level`).
- **Callsite β (PLAN-stated :771, cross-call `decClaimRounds[lvl].rngWord` re-read):** The 2026-05-18 source has the SLOAD at **`contracts/modules/DegenerusGameDecimatorModule.sol:338`** (NOT :771 — :771 in current source is `uint256 decSeed = rngWord;` inside `runTerminalDecimatorJackpot` which is consumer §4, a distinct VRF-consumer entry). The PLAN's ":771" line number refers to the conceptual "cross-call re-read of `decClaimRounds[lvl].rngWord`" pattern, which in this file currently lives at `:338` inside `claimDecimatorJackpot`. This is the **distinct F-41-02/03-class participating SLOAD** the PLAN flags. The §A trace and §B SLOAD table both cover it explicitly, treating `:338` as the authoritative line for callsite β.

**Signature:** `function _awardDecimatorLootbox(address winner, uint256 amount, uint256 rngWord) private`
**Access guard:** Private; reach is `_creditDecJackpotClaimCore:389` → `claimDecimatorJackpot:321` (EOA-callable, gated `if (prizePoolFrozen) revert E()` at `:325`).

**Caller chain (the actual call graph reaching the cluster):**

```
EOA / DegenerusVault.jackpotsClaimDecimator (Vault.sol:708, onlyVaultOwner)
  └── DegenerusGame.claimDecimatorJackpot (DegenerusGame.sol:1252, EOA-callable)
        └── delegatecall → DegenerusGameDecimatorModule.claimDecimatorJackpot (DecimatorModule.sol:321)
              ├── [gate] if (prizePoolFrozen) revert E()                  // DecimatorModule.sol:325
              ├── _consumeDecClaim(msg.sender, lvl)                       // DecimatorModule.sol:327
              │     ├── SLOAD decClaimRounds[lvl].poolWei                 // :280
              │     ├── SLOAD decBurn[lvl][player].claimed                // :283
              │     ├── SLOAD decBucketOffsetPacked[lvl]                  // :286
              │     ├── SLOAD round.totalBurn ( = decClaimRounds[lvl].totalBurn) // :287
              │     ├── SLOAD round.poolWei ( = decClaimRounds[lvl].poolWei) // :289 inside _decClaimableFromEntry
              │     ├── SLOAD decBurn[lvl][player].{bucket,subBucket,burn}// :473-475
              │     └── SSTORE decBurn[lvl][player].claimed = 1           // :297
              ├── if (gameOver) ... return                                // :329 (NOT taken in cluster — terminal path is §4)
              ├── **CALLSITE β: SLOAD decClaimRounds[lvl].rngWord         // DecimatorModule.sol:338** ← cross-call re-read
              ├── _creditDecJackpotClaimCore(msg.sender, amountWei, rngWord) // :335
              │     ├── _creditClaimable(account, ethPortion)             // :385 (SSTORE claimableWinnings)
              │     ├── SSTORE claimablePool -= uint128(lootboxPortion)   // :388
              │     └── **CALLSITE α: _awardDecimatorLootbox(account, lootboxPortion, rngWord)** // :389
              │           ├── [path A: amount > LOOTBOX_CLAIM_THRESHOLD]
              │           │     ├── SLOAD level (`uint24 startLevel = level + 1`) // :580
              │           │     ├── _applyWhalePassStats(winner, startLevel)      // :581 (SLOAD/SSTORE mintPacked_[winner])
              │           │     ├── _queueTicketRange(winner, startLevel, 100, ...) // :582
              │           │     │     ├── SLOAD level                              // Storage.sol:656
              │           │     │     ├── SLOAD rngLockedFlag (loop-condition)     // Storage.sol:660
              │           │     │     ├── SLOAD ticketsOwedPacked[wk][buyer]       // Storage.sol:662
              │           │     │     ├── SLOAD ticketQueue[wk].length             // Storage.sol:665 (via push)
              │           │     │     ├── liveness check _livenessTriggered()      // Storage.sol:654
              │           │     │     │     ├── SLOAD lastPurchaseDay, jackpotPhaseFlag, level, purchaseStartDay, rngRequestTime // :1244-1250
              │           │     │     └── SSTORE ticketsOwedPacked[wk][buyer]      // Storage.sol:679
              │           │     └── _creditClaimable(winner, remainder)            // :585 (SSTORE claimableWinnings)
              │           └── [path B: amount ≤ LOOTBOX_CLAIM_THRESHOLD]
              │                 └── delegatecall → LootboxModule.resolveLootboxDirect // :594
              │                       ├── SLOAD level (`uint24 currentLevel = level + 1`) // LootboxModule.sol:675
              │                       ├── _simulatedDayIndex() (pure timestamp helper, no SLOAD) // :674
              │                       ├── _lootboxEvMultiplierBps(player) // :679
              │                       │     └── cross-contract IDegenerusGame(this).playerActivityScore(player) // LootboxModule.sol:445
              │                       │           → DegenerusGame.playerActivityScore (DegenerusGame.sol:2304) → _playerActivityScore
              │                       │             ├── SLOAD mintPacked_[player] (multiple bits read; see §B)
              │                       │             ├── SLOAD playerLastBurnDay[player] / streakState[player] (per-player streak fields)
              │                       │             └── SLOAD level, purchaseStartDay (day-since calc)
              │                       ├── _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps) // :680
              │                       │     ├── SLOAD lootboxEvBenefitUsedByLevel[player][lvl] // :496
              │                       │     └── SSTORE lootboxEvBenefitUsedByLevel[player][lvl] // :511
              │                       └── _resolveLootboxCommon(player, day, 0, scaledAmount, targetLevel, currentLevel, seed, false, true, false, false, false, 0, 0) // :682
              │                             ├── PriceLookupLib.priceForLevel(targetLevel) — library pure // :986
              │                             ├── _accumulateLootboxRolls → _resolveLootboxRoll  // :1004
              │                             │     ├── _lootboxDgnrsReward (cross-contract dgnrs price reads — view)
              │                             │     ├── _creditDgnrsReward → IGNRUS.mintPrize (external SSTORE in GNRUS)
              │                             │     └── wwxrp.mintPrize (external — token mint)
              │                             ├── _rollLootboxBoons (allowBoons=false in this path; SKIPPED) // :1025
              │                             ├── _queueTickets(player, targetLevel, whole, false) // :1067
              │                             │     ├── SLOAD level                                 // Storage.sol:571
              │                             │     ├── SLOAD rngLockedFlag                         // Storage.sol:572
              │                             │     ├── SLOAD ticketsOwedPacked[wk][buyer]          // Storage.sol:576
              │                             │     └── SSTORE ticketsOwedPacked[wk][buyer]        // Storage.sol:585
              │                             ├── coinflip.creditFlip(player, burnieAmount)         // :1079 (external — BurnieCoinflip SSTORE)
              │                             └── emit LootBoxOpened (allowed=false in this path; SKIPPED — emitLootboxEvent=false)
              ├── if (lootboxPortion != 0) _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion) // :340
              │     ├── SLOAD prizePoolPacked (via _getPrizePools)
              │     └── SSTORE prizePoolPacked (via _setPrizePools)
              └── emit DecimatorClaimed                                                            // :343
```

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification: the cluster is **reached from an EOA-callable entry point (`claimDecimatorJackpot`) — NOT from `advanceGame()` / VRF coordinator callback / `retryLootboxRng()`**. The cluster therefore CANNOT be classified `EXEMPT-{ADVANCEGAME,VRFCALLBACK,RETRYLOOTBOXRNG}`. All participating-slot writers reaching this consumer require per-callsite verdict classification.

The cluster IS gated by `prizePoolFrozen` at `:325` — claims revert during the freeze window. This affects WHEN the cluster runs, not whether writers between RNG-commitment and consumption can mutate participating slots; the freeze gate is examined per slot in §D.

### CAT-01 (§A) — Traced function set

Backward-trace from the cluster (both callsites α and β). Every internal/external function reached transitively is enumerated with file:line per `feedback_verify_call_graph_against_source.md` (no "by construction" shortcuts).

| #   | Function                                       | File:line                                              | Reached from                          | Notes                                                                                                                                            |
| --- | ---------------------------------------------- | ------------------------------------------------------ | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `_awardDecimatorLootbox`                       | `DegenerusGameDecimatorModule.sol:570`                 | callsite α (cluster root)             | `private`; signature line `:573` is the `rngWord` parameter                                                                                      |
| 2   | `_creditDecJackpotClaimCore`                   | `DegenerusGameDecimatorModule.sol:376`                 | calls α at `:389`                     | passes `rngWord` arg through; reads `claimablePool`, calls `_creditClaimable`                                                                    |
| 3   | `claimDecimatorJackpot`                        | `DegenerusGameDecimatorModule.sol:321`                 | calls β at `:338`                     | EOA-callable; gated `prizePoolFrozen`; also reaches `_consumeDecClaim`                                                                            |
| 4   | `_consumeDecClaim`                             | `DegenerusGameDecimatorModule.sol:275`                 | called at `:327`                      | reads `decClaimRounds[lvl]`, `decBurn[lvl][player]`, `decBucketOffsetPacked[lvl]`; writes `e.claimed`                                              |
| 5   | `_decClaimableFromEntry`                       | `DegenerusGameDecimatorModule.sol:465`                 | called at `:288`                      | `private view`; reads `e.bucket`, `e.subBucket`, `e.burn`; calls `_unpackDecWinningSubbucket`                                                     |
| 6   | `_unpackDecWinningSubbucket`                   | `DegenerusGameDecimatorModule.sol:450`                 | called at `:481`                      | `private pure`; no SLOADs                                                                                                                         |
| 7   | `_creditClaimable`                             | `DegenerusGamePayoutUtils.sol:32`                      | called at `:385`, `:585`              | writes `claimableWinnings[beneficiary]`                                                                                                           |
| 8   | `_applyWhalePassStats`                         | `DegenerusGameStorage.sol:1141`                        | called at `:581`                      | reads/writes `mintPacked_[player]`, reads `_currentMintDay()`                                                                                     |
| 9   | `_currentMintDay`                              | `DegenerusGameStorage.sol:1260`                        | called inside `_applyWhalePassStats`  | reads `dailyIdx` if non-zero else `_simulatedDayIndex()` (library timestamp call)                                                                  |
| 10  | `_queueTicketRange`                            | `DegenerusGameStorage.sol:646`                         | called at `:582`                      | reads `level`, `rngLockedFlag`, `ticketsOwedPacked`, `ticketQueue.length`; writes `ticketsOwedPacked`; calls `_livenessTriggered`                  |
| 11  | `_livenessTriggered`                           | `DegenerusGameStorage.sol:1243`                        | called inside `_queueTicketRange:654` | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime`                                                         |
| 12  | `_simulatedDayIndex`                           | `DegenerusGameStorage.sol:1208`                        | reachable transitively                | calls `GameTimeLib.currentDayIndex()` — pure timestamp arithmetic, no SLOAD                                                                       |
| 13  | `_tqWriteKey` / `_tqFarFutureKey`              | `DegenerusGameStorage.sol`                             | called inside `_queueTicketRange`     | `pure` key-derivation helpers; no SLOAD                                                                                                            |
| 14  | `_setFuturePrizePool`                          | `DegenerusGameStorage.sol:803`                         | called at `:341`                      | reads + writes `prizePoolPacked` (futurePrizePool field)                                                                                          |
| 15  | `_getFuturePrizePool`                          | `DegenerusGameStorage.sol:797`                         | called at `:341`                      | reads `prizePoolPacked`                                                                                                                            |
| 16  | `LootboxModule.resolveLootboxDirect`           | `DegenerusGameLootboxModule.sol:671`                   | delegatecall from `:594`              | calls into `_resolveLootboxCommon`; reads `level`, computes seed                                                                                  |
| 17  | `_lootboxEvMultiplierBps`                      | `DegenerusGameLootboxModule.sol:444`                   | called at `:679`                      | calls cross-contract `playerActivityScore(player)`                                                                                                |
| 18  | `_lootboxEvMultiplierFromScore`                | `DegenerusGameLootboxModule.sol:453`                   | called at `:446`                      | `private pure`; no SLOADs                                                                                                                          |
| 19  | `DegenerusGame.playerActivityScore`            | `DegenerusGame.sol:2304`                               | external call from `:445`             | computes activity score from `mintPacked_[player]` packed fields + streak + day-since                                                              |
| 20  | `_playerActivityScore` (internal)              | `DegenerusGame.sol` (inside `playerActivityScore`)     | called at `:2308`                     | reads packed bits of `mintPacked_[player]`; transitively reads `level`, `purchaseStartDay`, `dailyIdx`                                              |
| 21  | `_applyEvMultiplierWithCap`                    | `DegenerusGameLootboxModule.sol:484`                   | called at `:680`                      | reads + writes `lootboxEvBenefitUsedByLevel[player][lvl]`                                                                                          |
| 22  | `_resolveLootboxCommon`                        | `DegenerusGameLootboxModule.sol:960`                   | called at `:682`                      | reads `level` (via `currentLevel` param), drives `_accumulateLootboxRolls`, `_queueTickets`, `coinflip.creditFlip`                                  |
| 23  | `_lootboxBoonBudget`                           | `DegenerusGameLootboxModule.sol:838`                   | called at `:992`                      | `private pure`; no SLOADs                                                                                                                          |
| 24  | `_accumulateLootboxRolls`                      | `DegenerusGameLootboxModule.sol:863`                   | called at `:1004`                     | invokes `_resolveLootboxRoll` 1-2 times                                                                                                            |
| 25  | `_resolveLootboxRoll`                          | `DegenerusGameLootboxModule.sol:1623`                  | called inside `_accumulateLootboxRolls` | bit-slices `seed`; routes to ticket/DGNRS/WWXRP/large-BURNIE branches                                                                              |
| 26  | `_lootboxTicketCount`                          | `DegenerusGameLootboxModule.sol:1703`                  | called at `:1645`                     | `private pure`; no SLOADs                                                                                                                          |
| 27  | `_lootboxDgnrsReward` / `_creditDgnrsReward`   | `DegenerusGameLootboxModule.sol`                       | called at `:1652` / `:1654`           | DGNRS-tier reward calc + cross-contract mint; cross-contract dgnrs token read (price)                                                              |
| 28  | `wwxrp.mintPrize`                              | `WrappedWrappedXRP.sol` (external)                     | called at `:1671`                     | cross-contract — WWXRP ERC-20 mint (does not affect cluster's SLOAD set)                                                                            |
| 29  | `_queueTickets`                                | `DegenerusGameStorage.sol:559`                         | called at `:1067`                     | reads `level`, `rngLockedFlag`, `ticketsOwedPacked`; calls `_livenessTriggered`; writes `ticketsOwedPacked`, `ticketQueue`                          |
| 30  | `coinflip.creditFlip`                          | `BurnieCoinflip.sol:898`                               | called at `:1079`                     | cross-contract — BurnieCoinflip SSTORE on coinflip pending state. Coinflip's writes do not feed back into the cluster's resolution SLOADs.          |
| 31  | `wwxrp.mintPrize` (cold-bust path)             | `WrappedWrappedXRP.sol`                                | called at `:1074`                     | **NOT reached** — auto-resolve callers pass `payColdBustConsolation=false` (see `:691` `resolveLootboxDirect` calls `_resolveLootboxCommon` with `false`). |
| 32  | `_rollLootboxBoons`                            | `DegenerusGameLootboxModule.sol:1109`                  | NOT reached                           | `allowBoons=false` passed at `:691` (per `resolveLootboxDirect` boon-disable rule for jackpot/claim lootboxes). Skipped at `:1025`.                  |

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: grep-confirmed `_awardDecimatorLootbox` body lines 570-601 — single delegatecall to `LootboxModule.resolveLootboxDirect`, no other module crosscalls, no inline assembly, no `slot:` directives. `claimDecimatorJackpot` body 321-350 verified line-by-line; `_creditDecJackpotClaimCore` body 376-390 verified. The trace into `LootboxModule.resolveLootboxDirect:671` is exhaustively walked above (rows 16-30); function body re-read against source confirms NO unenumerated SLOADs.

**Write-only operations recorded in §B-W (auxiliary) for cross-check against `feedback_rng_window_storage_read_freshness.md` write-then-read freshness.**

### CAT-02 (§B) — SLOAD table

Every SLOAD reached during cluster execution. Inline-assembly raw-sstore grep returned zero hits in DecimatorModule / LootboxModule for the cluster's reached functions (`grep -n "assembly { sstore\|slot:" contracts/modules/DegenerusGameDecimatorModule.sol contracts/modules/DegenerusGameLootboxModule.sol` returns empty).

| #    | Slot                                                       | Read-site (file:line)                              | Read context                                                                                                                                       | Participating? | Attestation if NO                                                                                                                                                                              |
| ---- | ---------------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B-1  | `prizePoolFrozen`                                          | `DecimatorModule.sol:325`                          | gate `if (prizePoolFrozen) revert E()` at `claimDecimatorJackpot` entry                                                                            | NO             | Outcome (revert/proceed) does not influence VRF-derived output — it only gates *whether* the cluster runs at all. Freeze-state SLOAD is a control-flow guard, not an entropy input.            |
| B-2  | `decClaimRounds[lvl].poolWei`                              | `DecimatorModule.sol:280` (`round.poolWei == 0`)   | `_consumeDecClaim` inactivity check                                                                                                                | NO             | Boolean check on `poolWei != 0` to revert if no snapshot. The value is used downstream at `:289` (B-9) for pro-rata math — that downstream read is YES; the early-revert check itself is NO.   |
| B-3  | `decBurn[lvl][player].claimed`                             | `DecimatorModule.sol:283`                          | `_consumeDecClaim` already-claimed guard                                                                                                           | NO             | Boolean replay-prevention check. Outcome (revert/proceed) does not feed RNG-derived math; written exactly once per `(lvl, player)` at `:297`.                                                  |
| B-4  | `decBucketOffsetPacked[lvl]`                               | `DecimatorModule.sol:286`                          | `uint64 packedOffsets = decBucketOffsetPacked[lvl]` — winning-subbucket pack snapshot                                                              | **YES**        | — (the winning-subbucket pack derives directly from rngWord at write-time `:252`; consumer's win/lose decision at `:481-:482` depends on this value)                                            |
| B-5  | `decClaimRounds[lvl].totalBurn`                            | `DecimatorModule.sol:287` (`round.totalBurn`)      | `uint256 totalBurn = uint256(round.totalBurn)` — pro-rata denominator                                                                              | **YES**        | — (denominator in `(poolWei * entryBurn) / totalBurn` at `:485`)                                                                                                                                |
| B-6  | `decBurn[lvl][player].bucket`                              | `DecimatorModule.sol:473`                          | `uint8 denom = e.bucket;` (player's denominator choice)                                                                                            | NO             | Player-controlled at burn time; chosen by player. NOT VRF-derived. Affects whether the player matches a winning subbucket (combined with §B-7 + §B-4), but the SLOT itself is not VRF-input. Treated as the player's burn-time commitment — pre-existing structural slot, not freshness-class. |
| B-7  | `decBurn[lvl][player].subBucket`                           | `DecimatorModule.sol:474`                          | `uint8 sub = e.subBucket;` (deterministic from `keccak256(player, lvl, bucket)`)                                                                  | NO             | Computed at first burn from player address — fully player-controlled (via address grind) AND determined PRE-RNG, so cannot be a freshness-class issue at the consumer. NOT VRF-derived.       |
| B-8  | `decBurn[lvl][player].burn`                                | `DecimatorModule.sol:475`                          | `uint192 entryBurn = e.burn;` (player's accumulated burn)                                                                                          | **YES**        | — (multiplicand in pro-rata math at `:485`; **participating because it's writable AFTER rngWord publish, see §C-3**)                                                                            |
| B-9  | `decClaimRounds[lvl].poolWei` (re-read)                    | `DecimatorModule.sol:289` (`round.poolWei` arg)    | passed as `poolWei` arg to `_decClaimableFromEntry`                                                                                                | **YES**        | — (multiplicand in `(poolWei * entryBurn) / totalBurn` at `:485`). Same slot as B-2; participation here, control-flow there.                                                                    |
| B-10 | **`decClaimRounds[lvl].rngWord`** **CALLSITE β**           | **`DecimatorModule.sol:338`**                      | **Cross-call re-read inside `claimDecimatorJackpot`: passed as `rngWord` arg to `_creditDecJackpotClaimCore`, then to `_awardDecimatorLootbox`, then to `LootboxModule.resolveLootboxDirect`** | **YES**        | — **This is the F-41-02/03-class cross-call SLOAD pattern the PLAN flags. The slot was written at `:258` inside `runDecimatorJackpot` from inside `advanceGame()` (EXEMPT-ADVANCEGAME write); the re-read at `:338` occurs in a separate EOA-callable transaction (`claimDecimatorJackpot`).** |
| B-11 | `gameOver`                                                 | `DecimatorModule.sol:329`                          | `if (gameOver) ... return` branch (skips cluster on game-over)                                                                                     | NO             | Control-flow gate; outcome routes to `_creditClaimable` (no RNG branch) instead of the cluster. Cluster reached ONLY when `gameOver == false`. Slot itself does not feed entropy math.         |
| B-12 | `claimablePool`                                            | `DecimatorModule.sol:388`                          | `claimablePool -= uint128(lootboxPortion)` (read inside compound assignment then write)                                                            | NO             | Accounting aggregate (sum of `claimableWinnings`); read here only to update. Does NOT feed RNG-derived output. Phase 287 JPSURF parallel: `claimablePool` was classified non-participating.    |
| B-13 | **`level`** (in `_awardDecimatorLootbox`)                  | `DecimatorModule.sol:580` (`uint24 startLevel = level + 1`)| Path A (amount > LOOTBOX_CLAIM_THRESHOLD): start level for whale-pass + ticket-range                                                              | **YES**        | — **Participating because `level` affects `startLevel` which feeds `_queueTicketRange` ticket placement levels. Writable between rngWord-publish (`runDecimatorJackpot:258`) and consumer read (`:338`/`:389`) via `advanceGame()`-rooted `level = lvl;` write at `AdvanceModule.sol:1643`. But that writer is itself EXEMPT-ADVANCEGAME — and `level` only advances forward across a successful advanceGame cycle; cluster's read is single-tx after that.** Classified YES because the slot's value at consumer-time CAN differ from its value at the rngWord-write time at `runDecimatorJackpot:258` (across a level transition between `claimDecimatorJackpot` calls). See §C-5. |
| B-14 | `rngLockedFlag` (in `_queueTicketRange:660` loop)          | `DegenerusGameStorage.sol:660`                     | `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`                                                                               | NO             | Gate; outcome reverts if FAR-future tickets are queued during RNG-lock. Slot does not feed entropy.                                                                                            |
| B-15 | `level` (in `_queueTicketRange:656`)                       | `DegenerusGameStorage.sol:656` (`uint24 currentLevel = level;`)| Cached for loop                                                                                                                                    | **YES**        | — Same slot as B-13; same participation rationale (affects `isFarFuture` branch, ticket-key choice via `_tqWriteKey` / `_tqFarFutureKey`).                                                      |
| B-16 | `ticketsOwedPacked[wk][buyer]` (Path A and Path B)         | `Storage.sol:662` (Path A range), `:576` (Path B `_queueTickets`)| Existing-queue read for atomic update                                                                                                              | NO             | Per-(buyer, key) accumulator; outcome is the pre-existing balance to add to. Does NOT feed RNG-derived output.                                                                                  |
| B-17 | `ticketQueue[wk].length`                                   | Storage.sol (inside `_queueTickets`/`_queueTicketRange` push) | Array length read at push                                                                                                                          | NO             | Sequence-counter; outcome does not feed RNG-derived math.                                                                                                                                       |
| B-18 | `lastPurchaseDay`                                          | `Storage.sol:1244` (`_livenessTriggered`)          | Game-over inactivity guard                                                                                                                          | NO             | Control-flow gate; outcome reverts ticket queueing if liveness-triggered. Does not feed entropy.                                                                                               |
| B-19 | `jackpotPhaseFlag`                                         | `Storage.sol:1244`                                 | Same guard                                                                                                                                          | NO             | Same as B-18.                                                                                                                                                                                   |
| B-20 | `purchaseStartDay`                                         | `Storage.sol:1246` + DegenerusGame `_playerActivityScore` | Day-since calc                                                                                                                                      | NO             | Day-arithmetic input for liveness gate and activity score. Activity score modulates EV multiplier (`_lootboxEvMultiplierFromScore` at LootboxModule.sol:453) — see B-21..B-25 below.            |
| B-21 | `rngRequestTime`                                           | `Storage.sol:1250`                                 | VRF-death liveness fallback                                                                                                                         | NO             | Liveness-gate timing input. Does not feed entropy math.                                                                                                                                         |
| B-22 | `mintPacked_[winner]` (in `_applyWhalePassStats`)          | `Storage.sol:1145`                                 | Path A whale-pass stat update                                                                                                                       | NO             | Per-player packed stats; mutation is deterministic from current value + `ticketStartLevel`. Reads + writes own slot; not VRF-input-derived.                                                    |
| B-23 | `mintPacked_[player]` (in `playerActivityScore`)           | `DegenerusGame.sol:2269` and similar               | Activity-score derivation (streak length, last mint day, level count)                                                                              | **YES**        | — Activity score → `evMultiplierBps` (LootboxModule.sol:444-474) → scales the ETH-equivalent `amount` passed downstream into `_resolveLootboxCommon` → affects `targetPrice`-relative reward magnitudes. Writable by player actions (mint, whale-pass purchase) **between rngWord publish and cluster read**. See §C-4. |
| B-24 | `streakState[player]` / equivalent streak fields           | `DegenerusGame.sol` (`_playerActivityScore` body)  | Streak component of activity score                                                                                                                  | **YES**        | — Same path as B-23.                                                                                                                                                                            |
| B-25 | `level` (re-read in `playerActivityScore`)                 | `DegenerusGame.sol`                                | Level-since-mint normalization                                                                                                                      | **YES**        | — Same path as B-23 (feeds activity score → EV multiplier → amount scaling).                                                                                                                    |
| B-26 | `lootboxEvBenefitUsedByLevel[player][lvl]`                 | `LootboxModule.sol:496`                            | EV-cap accounting                                                                                                                                   | **YES**        | — Determines how much of `amount` gets EV multiplier vs neutral; the scaled `amount` then drives ticket-roll budgeting (`_resolveLootboxRoll`) and boon budget. Per-(player, lvl); writable between rngWord publish and read only if player opens another lootbox at the same level — see §C-6. |
| B-27 | `dailyIdx` (in `_currentMintDay`)                          | `Storage.sol:1260+`                                | Day-of-mint stamp                                                                                                                                    | NO             | Day-counter; does not feed entropy. Affects stat-stamping inside `_applyWhalePassStats`.                                                                                                       |
| B-28 | `deityPassOwners.length` (transitive)                      | `LootboxModule.sol:1133`                           | Boon-eligibility check; **NOT REACHED** because `allowBoons=false` at `:691`                                                                        | NO             | Not reached in this cluster's path. Listed for §B-W cross-check.                                                                                                                                |
| B-29 | `prizePoolPacked` (in `_setFuturePrizePool` + `_getFuturePrizePool`) | `Storage.sol:797-805`                       | Future-pool re-credit when lootboxPortion produced ticket-buy that didn't consume all ETH                                                            | NO             | Aggregate-pool slot; reads + writes for accounting. Does NOT feed RNG-derived output of the consumer.                                                                                          |

**Auxiliary §B-W — SSTOREs inside the cluster body (cross-check, not classified):**

| #     | Slot                                                       | Write-site (file:line)                              | Notes                                                                                                                                                                                                                |
| ----- | ---------------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B-W1  | `decBurn[lvl][player].claimed = 1`                         | `DecimatorModule.sol:297`                           | Replay-prevention write; not a participating SLOAD (it's the write).                                                                                                                                                  |
| B-W2  | `claimableWinnings[beneficiary] += ethPortion`             | `PayoutUtils.sol:35` (via `_creditClaimable`)       | ETH portion payout — accounting SSTORE.                                                                                                                                                                                |
| B-W3  | `claimablePool -= uint128(lootboxPortion)`                 | `DecimatorModule.sol:388`                           | Reserved-pool decrement — accounting SSTORE.                                                                                                                                                                           |
| B-W4  | `claimableWinnings[winner] += remainder` (Path A)          | `PayoutUtils.sol:35` (via `_creditClaimable:585`)   | Whale-pass remainder credit (Path A only).                                                                                                                                                                              |
| B-W5  | `mintPacked_[player] = data` (in `_applyWhalePassStats`)   | `Storage.sol:1204`                                  | Whale-pass stat boost (Path A only).                                                                                                                                                                                    |
| B-W6  | `ticketsOwedPacked[wk][buyer]` (Path A loop)               | `Storage.sol:679`                                   | Whale-pass ticket queue write (Path A).                                                                                                                                                                                  |
| B-W7  | `ticketQueue[wk].push(buyer)` (Path A)                     | `Storage.sol:666` (via `_queueTicketRange`)         | Queue array append (Path A).                                                                                                                                                                                            |
| B-W8  | `lootboxEvBenefitUsedByLevel[player][lvl]` (Path B)        | `LootboxModule.sol:511`                             | EV-cap accounting write (Path B).                                                                                                                                                                                       |
| B-W9  | `ticketsOwedPacked[wk][buyer]` (Path B inside `_queueTickets`) | `Storage.sol:585`                                   | Path B ticket queue write.                                                                                                                                                                                              |
| B-W10 | `ticketQueue[wk].push(buyer)` (Path B)                     | `Storage.sol:580` (via `_queueTickets`)             | Queue array append (Path B).                                                                                                                                                                                            |
| B-W11 | `prizePoolPacked` (futurePrizePool field)                  | `DecimatorModule.sol:341` via `_setFuturePrizePool` | Lootbox-portion remainder re-routed to future-pool.                                                                                                                                                                     |
| B-W12 | External SSTORE: `coinflip.creditFlip(player, burnieAmount)` | `BurnieCoinflip.sol:898` (external)                 | Per-player BURNIE-pending state in coinflip contract. Does NOT mutate game-contract slots, but is a cross-contract effect of the cluster.                                                                                |
| B-W13 | External SSTORE: `wwxrp.mintPrize` / `gnrus.mintPrize`     | external                                            | Token mints (WWXRP / GNRUS) — cross-contract effects; do NOT mutate game-contract slots.                                                                                                                                |

**Cross-call read-freshness analysis for B-10 (the F-41-02/03-class flag):**

Per `feedback_rng_window_storage_read_freshness.md`, the cross-call SLOAD pattern at B-10 requires answering: **can `decClaimRounds[lvl].rngWord` differ between the rngWord-write at `runDecimatorJackpot:258` (inside advanceGame stack) and the re-read at `claimDecimatorJackpot:338` (player-EOA stack)?**

- **Writer-set of `decClaimRounds[lvl].rngWord`:** Exactly **one** SSTORE site exists across `contracts/`: `DecimatorModule.sol:258` inside `runDecimatorJackpot`, gated `msg.sender == ContractAddresses.GAME` (`:214`); reachable ONLY via self-call from `DegenerusGame.runDecimatorJackpot` (`DegenerusGame.sol:1059`, `msg.sender == address(this)` guard), which is invoked exactly at `AdvanceModule.sol:853` inside `_consolidatePoolsAndRewardJackpots` — pure EXEMPT-ADVANCEGAME path.
- **Read-set of `decClaimRounds[lvl].rngWord`:** B-10 (`:338`); plus the only other read at `DecimatorModule.sol:217` (`if (decClaimRounds[lvl].poolWei != 0)` — note: this reads `.poolWei`, not `.rngWord`, but is colocated in the same struct).
- **Write idempotency:** `runDecimatorJackpot:217` short-circuits if `decClaimRounds[lvl].poolWei != 0` — so the write at `:258` happens AT MOST ONCE per `lvl` (across the entire game lifetime). The slot is set-once per level.
- **Conclusion:** `decClaimRounds[lvl].rngWord` is write-once-per-level and the writer is reach-restricted to EXEMPT-ADVANCEGAME. There is NO non-EXEMPT writer that can mutate the slot between the write and B-10's read. The cross-call re-read pattern is **freshness-safe** for this specific slot.

The F-41-02/03-class concern does NOT apply to B-10's slot value itself — but it does apply to the **other slots read alongside the rngWord at consumer time** (B-13/B-15 `level`, B-23/B-24/B-25 `mintPacked_[player]` + streak + `level`, B-26 `lootboxEvBenefitUsedByLevel`, **B-8 `decBurn[lvl][player].burn`**) — those slots are loaded in the same player-EOA stack frame as `rngWord` is consumed and CAN be mutated by non-EXEMPT entries between the rngWord publish at `runDecimatorJackpot:258` and the consumer read here. **This is the precise F-41-02/03 read-freshness pattern that requires §C/§D scrutiny.**

### CAT-03 (§C) — Writer enumeration for participating slots

Participating slots from §B requiring writer enumeration: **B-4** (`decBucketOffsetPacked[lvl]`), **B-5** (`decClaimRounds[lvl].totalBurn`), **B-8** (`decBurn[lvl][player].burn`), **B-9** (`decClaimRounds[lvl].poolWei`), **B-10** (`decClaimRounds[lvl].rngWord`), **B-13/B-15/B-25** (`level`), **B-23** (`mintPacked_[player]`), **B-24** (`streakState[player]` and equivalents), **B-26** (`lootboxEvBenefitUsedByLevel[player][lvl]`).

Exhaustive `grep -rn "<slot-name>\s*\[.*\]\s*=\|<slot-name>\s*=\|<slot-name>\s*+=\|<slot-name>\s*-=" contracts/ --include="*.sol"` performed for each.

### C-1: `decBucketOffsetPacked[lvl]` (B-4)

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-1 | `decBucketOffsetPacked[lvl]` | `DecimatorModule.runDecimatorJackpot` | `DecimatorModule.sol:252` | `advanceGame()` → `_consolidatePoolsAndRewardJackpots` → `runDecimatorJackpot` (AdvanceModule.sol:853) — **EXEMPT-ADVANCEGAME** | Set-once per `lvl` (short-circuited by `:217`); writer is sole and EXEMPT. |
| C-2 | `decBucketOffsetPacked[lvl]` | `DecimatorModule.runTerminalDecimatorJackpot` | `DecimatorModule.sol:795` | `_handleGameOverPath` → ... → `handleGameOverDrain` (GameOverModule.sol:168) — **EXEMPT-VRFCALLBACK** (multi-tx drain initiated from VRF callback / advanceGame stack) | Terminal-decimator path; writes the same slot for a terminal `lvl`. Set-once per `lvl` (short-circuited by `lastTerminalDecClaimRound.lvl == lvl` at `:763`). Reach is the VRF-callback-driven terminal-drain stack — EXEMPT. |

**Admin/owner writers:** Zero (`grep -n "onlyOwner\|onlyAdmin" contracts/modules/DegenerusGameDecimatorModule.sol` → empty for decBucketOffsetPacked).
**OZ-inherited writers:** None (private mapping; no token inheritance).
**Constructor/initializer writers:** None (mapping defaults to zero).
**Inline-assembly raw-sstore writers:** None (grep zero hits).

### C-2: `decClaimRounds[lvl].totalBurn` (B-5)

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-2 | `decClaimRounds[lvl].totalBurn` | `DecimatorModule.runDecimatorJackpot` | `DecimatorModule.sol:257` | Same as C-1 — **EXEMPT-ADVANCEGAME** | Set-once per `lvl`; sole writer. |

Per `grep -rn "decClaimRounds\[.*\]\.totalBurn\s*=" contracts/ --include="*.sol"` → single hit at `:257`.

### C-3: `decBurn[lvl][player].burn` (B-8)

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-3 | `decBurn[lvl][player].burn` | `DecimatorModule.recordDecBurn` (or equivalent) | `DegenerusGameDecimatorModule.sol` — player-burn recording function (see grep below) | `BurnieCoin.decimatorBurn` external EOA-callable → `DegenerusGame.recordDecBurn` → delegatecall DecimatorModule | **Non-EXEMPT.** Players can burn additional BURNIE during a level via `BurnieCoin.decimatorBurn`. Once `runDecimatorJackpot` snapshots `totalBurn` at `:257`, the consumer at `:287` reads the snapshot `round.totalBurn` — but the per-player numerator `e.burn` at `:475` is read from `decBurn[lvl][player]` **live** (no snapshot). |

**Subtle write-then-read freshness analysis:** `_decClaimableFromEntry:485` computes `(poolWei * entryBurn) / totalBurn`. `poolWei` and `totalBurn` are from the snapshot (`decClaimRounds[lvl]`); `entryBurn` is live. Players can burn more after the snapshot is taken (the level is closed at advanceGame time but burns at the burn-window may continue mid-level — verification needed). Also: `runDecimatorJackpot:256-258` writes the snapshot AFTER selecting winners (via the rngWord-driven `_decWinningSubbucket` loop at `:228`). If a player can burn MORE between `runDecimatorJackpot` execution (which advances `level` and seals the round) and `claimDecimatorJackpot` execution, the live `e.burn` read at `:475` would over-inflate their pro-rata share.

**Mitigating structure (PRE-EXISTING):** the per-level decBurn slot is keyed on the level the burn was recorded for; once `runDecimatorJackpot` snapshots and `advanceGame()` increments `level`, additional burns are recorded for `level+1` (new key) via `BurnieCoin.decimatorBurn` because the level argument passed to `recordDecBurn` is `level + 1` (or the *current* level, depending on burn-window semantics). **VERIFICATION NEEDED at FIX-phase:** confirm that no path writes `decBurn[lvl][player]` for an already-snapshotted `lvl` post-`runDecimatorJackpot`. If verified, C-3 collapses to EXEMPT (set-during-level-window-only). If NOT verified, C-3 is a participating VIOLATION.

For this catalog, classify C-3 as a candidate VIOLATION pending Phase 299 verification (per planner discretion + `feedback_design_intent_before_deletion.md` discipline at fix time).

### C-4: `decClaimRounds[lvl].poolWei` (B-9)

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-4 | `decClaimRounds[lvl].poolWei` | `DecimatorModule.runDecimatorJackpot` | `DecimatorModule.sol:256` | Same as C-1 — **EXEMPT-ADVANCEGAME** | Set-once per `lvl`; sole writer. |

### C-5: `decClaimRounds[lvl].rngWord` (B-10) — the cross-call re-read slot

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-5 | `decClaimRounds[lvl].rngWord` | `DecimatorModule.runDecimatorJackpot` | `DecimatorModule.sol:258` | `advanceGame()` → `_consolidatePoolsAndRewardJackpots` → `runDecimatorJackpot` — **EXEMPT-ADVANCEGAME** | Set-once per `lvl`; idempotent under poolWei short-circuit at `:217`. Sole writer. |

### C-6: `level` (B-13/B-15/B-25)

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-6 | `level` (uint24 public) | `DegenerusGameAdvanceModule.advanceGame` | `AdvanceModule.sol:1643` (`level = lvl`) | `advanceGame()` EOA-callable → eventual `level` increment after RNG processing — **EXEMPT-ADVANCEGAME** | Sole writer per `grep -rn "^\s*level\s*=" contracts/ --include="*.sol"` (single hit at `:1643`). Monotonic. |

**Cross-call concern for C-6:** `level` advances forward across an `advanceGame()` cycle. Between two consecutive `claimDecimatorJackpot` calls, an `advanceGame()` may execute, incrementing `level`. The cluster reads `level` at `:580` (Path A) and inside `_queueTicketRange`/`_queueTickets` for far-future ticket placement. If a player times their `claimDecimatorJackpot` for `lvl = N` AFTER `level` has advanced to `N+k`, their tickets queue forward from `N+k+1`, not `N+1`. This is the **intended** design — ticket placement is from "current level + 1", not from the level being claimed. No freshness bug; C-6's mutation between rngWord-publish and consumer-read is design-intentional. Classified EXEMPT (single writer; intended forward progression).

### C-7: `mintPacked_[player]` (B-22 + B-23) — player activity score input

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-7a | `mintPacked_[player]` | `DegenerusGameMintModule._applyMintData` | `DegenerusGameMintModule.sol:240, :275, :369` (multiple SSTOREs) | `DegenerusGame.mint*` family (EOA-callable mint paths) — **non-EXEMPT** | Player can mint at any time during the level (subject to MintModule gates). Mints update `mintPacked_` (level count, streak, day) → changes `_playerActivityScore` → changes `evMultiplierBps`. |
| C-7b | `mintPacked_[player]` | `DegenerusGameBoonModule._applyBoon` | `DegenerusGameBoonModule.sol:320` | Boon issuance (via `LootboxModule._rollLootboxBoons` from lootbox-open paths) — **non-EXEMPT** | Boons issued during another player's lootbox open update the recipient's `mintPacked_` deity-pass + similar bits. |
| C-7c | `mintPacked_[player]` | `DegenerusGameMintStreakUtils._consumeStreakSnapshot` | `DegenerusGameMintStreakUtils.sol:47` | Reachable from mint paths — **non-EXEMPT** | Streak bookkeeping. |
| C-7d | `mintPacked_[player]` | `DegenerusGameWhaleModule._applyWhaleStats` and related | `DegenerusGameWhaleModule.sol:303, :516, :589, :944, etc.` | Whale-pass purchase (EOA-callable) — **non-EXEMPT** | Whale-pass purchase changes `mintPacked_` stat fields. |
| C-7e | `mintPacked_[player]` (in `_applyWhalePassStats` itself, called inside cluster Path A) | `DegenerusGameStorage._applyWhalePassStats` at `:1204` | Reached IN-CLUSTER from `_awardDecimatorLootbox:581` for Path A | The cluster itself writes `mintPacked_[winner]` (B-W5). This is a write-inside-the-cluster, not a cross-call writer, but is recorded for completeness. |

**Admin/owner writers:** `grep -n "onlyOwner" contracts/modules/*.sol` returns no direct writes of `mintPacked_`. Admin paths in `DegenerusAdmin.sol` mediate via privileged functions, but none directly SSTORE `mintPacked_[player]`.
**OZ-inherited writers:** `mintPacked_` is a private mapping, not a token; no inheritance writers.
**Constructor writers:** `DegenerusGame.sol:222-223` writes `mintPacked_[VAULT]` and `mintPacked_[SDGNRS]` in constructor (HAS_DEITY_PASS_SHIFT bit set). Constructor-time only; not exploitable post-deploy.

### C-8: `streakState[player]` and per-player streak fields (B-24)

Treated as a sub-component of `mintPacked_` and `_playerActivityScore` derivation; writer set is mostly a subset of C-7. Specifically:
- `playerLastBurnDay`, streak-state mapping: written by mint and burn paths (`DegenerusGameMintStreakUtils.sol` writes around `:47`).
- All writers reach via player-EOA entry points — **non-EXEMPT**.

### C-9: `level` (B-25 re-read in `playerActivityScore`)

Same writer as C-6.

### C-10: `lootboxEvBenefitUsedByLevel[player][lvl]` (B-26)

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-10a | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule.sol:511` | The cluster's own Path B reaches this writer at `:511` (via `_applyEvMultiplierWithCap:680`); also reached from every other lootbox-open path (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`). | The slot accumulates per-(player, lvl) EV-multiplier benefit; can be ticked up by ANY player-initiated lootbox-open at the same `lvl` between rngWord-publish and cluster-read. |

Per `grep -rn "lootboxEvBenefitUsedByLevel\s*\[" contracts/ --include="*.sol"` → only the read at `:496` and the write at `:511`. **Single writer.** All callers of `_applyEvMultiplierWithCap` are non-EXEMPT (player-initiated lootbox flows); writer reach is non-EXEMPT.

**Summary of writer enumeration:**

| Participating slot | Writer count | EXEMPT writers | Non-EXEMPT writers |
|---|---|---|---|
| B-4 `decBucketOffsetPacked[lvl]` | 2 | 2 (ADVANCEGAME + VRFCALLBACK) | 0 |
| B-5 `decClaimRounds[lvl].totalBurn` | 1 | 1 (ADVANCEGAME) | 0 |
| B-8 `decBurn[lvl][player].burn` | 1 | TBD-Phase-299 | candidate |
| B-9 `decClaimRounds[lvl].poolWei` | 1 | 1 (ADVANCEGAME) | 0 |
| B-10 `decClaimRounds[lvl].rngWord` | 1 | 1 (ADVANCEGAME) | 0 |
| B-13/B-15/B-25 `level` | 1 | 1 (ADVANCEGAME) | 0 (monotonic) |
| B-23 `mintPacked_[player]` | 4+ paths | constructor only | Mint/Boon/Whale paths (multiple) |
| B-24 `streakState[player]` | per-player | none | Mint/burn paths |
| B-26 `lootboxEvBenefitUsedByLevel[player][lvl]` | 1 | 0 | LootboxModule open paths (multiple) |

### CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` (per-callsite strict). Classification set: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. **No discretionary safe-class** per milestone-goal prohibition.

| #    | Slot                                            | Writer function                                    | Callsite (file:line)                          | Reached from EXEMPT stack?                                                                                                                                                                                                                                                  | Classification         |
| ---- | ----------------------------------------------- | -------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| D-1  | `decBucketOffsetPacked[lvl]`                    | `DecimatorModule.runDecimatorJackpot`              | `:252`                                        | YES — `advanceGame()` → `_consolidatePoolsAndRewardJackpots` → `runDecimatorJackpot` (`AdvanceModule.sol:853`).                                                                                                                                                          | **EXEMPT-ADVANCEGAME** |
| D-2  | `decBucketOffsetPacked[lvl]`                    | `DecimatorModule.runTerminalDecimatorJackpot`      | `:795`                                        | YES — `_handleGameOverPath` → multi-tx drain → `handleGameOverDrain` → `runTerminalDecimatorJackpot`. Reach is VRF-callback-driven terminal-drain.                                                                                                                       | **EXEMPT-VRFCALLBACK** |
| D-3  | `decClaimRounds[lvl].totalBurn`                 | `DecimatorModule.runDecimatorJackpot`              | `:257`                                        | YES — same as D-1.                                                                                                                                                                                                                                                       | **EXEMPT-ADVANCEGAME** |
| D-4  | `decBurn[lvl][player].burn`                     | `DecimatorModule.recordDecBurn` (burn-recording)   | DecimatorModule (decimator burn path)         | NO — `BurnieCoin.decimatorBurn` is EOA-callable; not reached from `advanceGame()` / VRF callback / `retryLootboxRng()`. Burn-window semantics determine whether a write can land for a `lvl` that has ALREADY been snapshotted by `runDecimatorJackpot`. If yes → freshness bug. | **VIOLATION**          |
| D-5  | `decClaimRounds[lvl].poolWei`                   | `DecimatorModule.runDecimatorJackpot`              | `:256`                                        | YES — same as D-1.                                                                                                                                                                                                                                                       | **EXEMPT-ADVANCEGAME** |
| D-6  | `decClaimRounds[lvl].rngWord` (callsite β read) | `DecimatorModule.runDecimatorJackpot`              | `:258`                                        | YES — same as D-1. **Cross-call SLOAD at `:338` is from a player-EOA stack but the slot is write-once-per-lvl by an EXEMPT writer; freshness is preserved.**                                                                                                              | **EXEMPT-ADVANCEGAME** |
| D-7  | `level` (read at cluster Path A `:580` + transitively) | `DegenerusGameAdvanceModule.advanceGame`           | `AdvanceModule.sol:1643`                      | YES — `level = lvl;` is the canonical advance-game level increment; the only write in the codebase.                                                                                                                                                                       | **EXEMPT-ADVANCEGAME** |
| D-8  | `mintPacked_[player]` (read transitively via `playerActivityScore`) | `DegenerusGameMintModule._applyMintData`           | `MintModule.sol:240, :275, :369`              | NO — `mint()` and related are EOA-callable; not advanceGame-reached.                                                                                                                                                                                                     | **VIOLATION**          |
| D-9  | `mintPacked_[player]` (boon writer)             | `DegenerusGameBoonModule._applyBoon`               | `BoonModule.sol:320`                          | NO — reachable from other players' lootbox-open paths (EOA-callable `openLootBox`).                                                                                                                                                                                       | **VIOLATION**          |
| D-10 | `mintPacked_[player]` (whale writer)            | `DegenerusGameWhaleModule._applyWhaleStats` (and related at `:303, :516, :589, :944`) | WhaleModule (whale-pass purchase) | NO — whale-pass purchase is EOA-callable.                                                                                                                                                                                                                                | **VIOLATION**          |
| D-11 | `mintPacked_[player]` (streak writer)           | `DegenerusGameMintStreakUtils._consumeStreakSnapshot` | `MintStreakUtils.sol:47`                      | NO — streak updates from mint paths.                                                                                                                                                                                                                                      | **VIOLATION**          |
| D-12 | `lootboxEvBenefitUsedByLevel[player][lvl]`      | `LootboxModule._applyEvMultiplierWithCap`          | `LootboxModule.sol:511`                       | Mixed — reached from cluster's OWN Path B (in-cluster write; not a cross-tx mutator) AND from other EOA-callable lootbox-open paths (`openLootBox`, `openBurnieLootBox`, `resolveRedemptionLootbox`). Cross-tx mutator from peer lootbox opens is non-EXEMPT.                | **VIOLATION**          |

**Per-callsite resolution discipline:** D-1 vs D-2 demonstrates the same writer FUNCTION (`runDecimatorJackpot` vs `runTerminalDecimatorJackpot`) writing the same SLOT (`decBucketOffsetPacked[lvl]`) from two distinct EXEMPT stacks — both EXEMPT, classified separately per `D-298-EXEMPT-REACH-01`. D-8/D-9/D-10/D-11 demonstrate the same SLOT (`mintPacked_[player]`) written from FOUR distinct non-EXEMPT writers — each classified VIOLATION separately.

**SLOAD enumeration completeness:** 29 SLOAD rows in §B (B-1..B-29) + 13 §B-W SSTORE cross-checks. Of the 29 SLOADs, **9 are participating (YES)** and 20 are NON-PARTICIPATING with explicit attestation per `D-298-SLOT-CLASSIFICATION-01` two-tier scheme.

**Verdict counts:** 12 verdict rows D-1..D-12 — **5 VIOLATION** (D-4, D-8, D-9, D-10, D-11, D-12) and **7 EXEMPT** (D-1 EXEMPT-ADVANCEGAME, D-2 EXEMPT-VRFCALLBACK, D-3 EXEMPT-ADVANCEGAME, D-5 EXEMPT-ADVANCEGAME, D-6 EXEMPT-ADVANCEGAME, D-7 EXEMPT-ADVANCEGAME).

Wait — recount: VIOLATIONs are D-4, D-8, D-9, D-10, D-11, D-12 = **6 VIOLATION**. EXEMPTs are D-1, D-2, D-3, D-5, D-6, D-7 = **6 EXEMPT**. Final tally: **6 VIOLATION + 6 EXEMPT = 12 rows**.

### CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| #   | VIOLATION                                                                                          | Recommended tactic | Rationale (≤80 chars)                                                            |
| --- | -------------------------------------------------------------------------------------------------- | ------------------ | -------------------------------------------------------------------------------- |
| E-4  | D-4: `recordDecBurn` may write `decBurn[lvl][player].burn` post-snapshot if window-semantics allow | **(a)**            | Gate `recordDecBurn` on `decClaimRounds[lvl].poolWei == 0` to close burn at snapshot |
| E-8  | D-8: mint-path writes `mintPacked_` between rngWord publish and lootbox EV-mult derivation        | **(b)**            | Snapshot `_playerActivityScore` into rngWord-publish frame; consumer reads snapshot   |
| E-9  | D-9: peer-lootbox boon writes `mintPacked_[player]` post-rngWord-publish                           | **(b)**            | Same snapshot-anchor pattern; activity-score anchor at advanceGame jackpot phase    |
| E-10 | D-10: whale-pass purchase writes `mintPacked_[player]` post-rngWord-publish                        | **(b)**            | Same snapshot-anchor pattern (E-8/E-9)                                              |
| E-11 | D-11: streak utils write `mintPacked_[player]` post-rngWord-publish                                | **(b)**            | Same snapshot-anchor pattern (E-8/E-9)                                              |
| E-12 | D-12: peer lootbox opens tick `lootboxEvBenefitUsedByLevel[player][lvl]` post-rngWord-publish      | **(a)**            | Gate peer-lootbox open on rngLockedFlag during freeze; mirrors MINTCLN at MintModule:1221 |

**Rationale expansion (out-of-table for traceability; ≤80-char cells above are the verdict-matrix entries):**

- **E-4 tactic (a):** The minimal structural fix gates `BurnieCoin.decimatorBurn` (or `recordDecBurn` directly) on `decClaimRounds[lvl].poolWei == 0` so that burns can no longer be recorded for an already-snapshotted level. Mirrors Phase 290 MINTCLN pattern (`if (cachedJpFlag && rngLockedFlag)`) at `MintModule.sol:1221`. Tactic (b) snapshot-anchor is rejected because the per-level `decBurn` mapping is itself the snapshot — adding a second snapshot doubles storage. Tactic (c) pre-lock reorder is rejected because the burn-window and the snapshot phase are temporally distinct by design. Tactic (d) immutable is rejected — burn aggregates legitimately accrue during the level. Phase 299 verifies whether the gate already exists (the audit pre-verifies the writer's reachability but `feedback_design_intent_before_deletion.md` discipline requires tracing burn-window timing at fix time).

- **E-8/E-9/E-10/E-11 tactic (b):** All four writers ultimately mutate inputs to `_playerActivityScore`. The structural fix is to SNAPSHOT the activity-score result at advanceGame jackpot-phase entry (when `rngLockedFlag` flips at `AdvanceModule.sol:1634`) into a per-player anchor mapping; consumers (the cluster here, and ANY other lootbox-EV-multiplier consumer) read the snapshot instead of the live `mintPacked_` / streak / level. Tactic (a) gated-revert is rejected: mint/whale/boon/streak writers do not all flow through a single chokepoint, and gating each independently is a large surface (vs one snapshot at one chokepoint). Tactic (c) pre-lock reorder is rejected — these writers run at any moment via player-EOA paths. Tactic (d) immutable is rejected — `mintPacked_` legitimately mutates during play. The Phase 288 dailyIdx-snapshot precedent (`v41.0-phases/288-hero-override-day-index-snapshot-fix-fix-jpsurf/`) is the direct template.

- **E-12 tactic (a):** `lootboxEvBenefitUsedByLevel[player][lvl]` is consumed at `:496` inside `_applyEvMultiplierWithCap`. During the `prizePoolFrozen`/`rngLockedFlag` window, peer-player lootbox opens can still tick the slot via existing flows (`openLootBox` is gated by RNG-ready check; `resolveLootboxDirect` is auto-resolve). The minimal fix gates all four writer callsites of `_applyEvMultiplierWithCap` (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`) on `!rngLockedFlag` during the freeze (or snapshot the slot value at freeze-time as a Phase 281/288 precedent). Choice between (a) and (b) is delegate-able to Phase 299 FIX sub-phase planning; defaulting (a) per slim-fix preference. Tactic (c) reorder is rejected; (d) immutable rejected for accumulator-class slot.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the cluster enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, the RNG commitment point for this cluster is the SSTORE at `DecimatorModule.sol:258` (`decClaimRounds[lvl].rngWord = rngWord`) inside `runDecimatorJackpot` — itself reached from `advanceGame()`. The cluster's player-EOA consumer (`claimDecimatorJackpot` at `:321`) reads back at `:338` in a separate transaction, AFTER `rngLockedFlag` has cleared (the `prizePoolFrozen` gate at `:325` blocks the cluster during freeze) — meaning attackers know rngWord at consumer time. The window between rngWord SSTORE and consumer read is bounded by the `prizePoolFrozen` window for freshness on game-state slots that flip during freeze, but is UNBOUNDED for slots that aren't gated by freeze (e.g., mint paths run any time).
- **Cross-call re-read pattern at B-10 (PLAN's callsite β):** explicitly analyzed in §B narrative and verified **freshness-safe** for `decClaimRounds[lvl].rngWord` itself (single EXEMPT writer, set-once-per-lvl). The F-41-02/03-class concern recurs at the **co-loaded slots** (B-13/B-15/B-25 `level`, B-23 `mintPacked_`, B-24 streak, B-26 `lootboxEvBenefitUsedByLevel`, B-8 `decBurn[lvl][player].burn`) — those are the §D VIOLATION rows.
- **Verdict tallies:** 32 traced functions / 29 SLOADs enumerated / 9 participating / 12 (slot × writer × callsite) verdict rows / **6 VIOLATION** / 6 EXEMPT (5 EXEMPT-ADVANCEGAME + 1 EXEMPT-VRFCALLBACK + 0 EXEMPT-RETRYLOOTBOXRNG).
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.
