# 388-03 — Byte-Freeze Pin + Audit-Delta Surface (FND-01)

The audit subject's byte-freeze fingerprint and the `77580320 → a8b702a7` audit-delta surface — the
content-addressed pin every later sweep (389–396) asserts against, and the file-family map that tells
each sweep planner its slice of the delta.

---

## 1. The byte-freeze pin (subject `a8b702a7`)

**Subject under audit:** `a8b702a7` — v63.0 audit subject, byte-frozen at FOUNDATION (Phase 388).
**Baseline (last formally audited):** `77580320` — the v62.0 closure subject.

**`contracts/` fingerprint (the byte-frozen pin):**

- **git tree-hash (content-addressed):** `git rev-parse a8b702a7:contracts` =
  `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
  This matches the 388-01 layout-key's recorded `contracts_tree_hash` (`2934d3d8987a09c5f073549a0cb499f6c5f28620`) — the same frozen subject Plan 01 inspected the storage layout against.
- **deterministic content sha256** (`find contracts -name '*.sol' | sort | xargs sha256sum | sha256sum`):
  `0c684378df8d12f339af54e39de7df55971643f69e6b68f02332e918c20d15b3`
  (60 contract-source `.sol` files; the second sha256 over the sorted per-file digests is path-stable
  and order-independent of filesystem walk order).

**Empty-diff assertion (subject byte-identical to the working tree):**

- `git diff a8b702a7 -- contracts/` is **EMPTY**.
- `git rev-parse HEAD:contracts` = `2934d3d8987a09c5f073549a0cb499f6c5f28620` ==
  `git rev-parse a8b702a7:contracts` — **the working tree's contract-source tree is byte-identical to
  the frozen subject.** HEAD is a later docs/planning-only commit (`a3cf5df9`, a `docs(388)` commit on
  top of the subject); what matters for the audit is that `HEAD:contracts == a8b702a7:contracts`,
  which holds.
- `git status --porcelain contracts/` is **EMPTY** (no uncommitted contract-source change;
  `ContractAddresses.sol` not regenerated — hardhat was never invoked in this task, per the landmine).

**Out of scope:** the untracked `PLAYER-PURCHASE-REWARDS.html` at the repo root is a player-facing
document, **not** a contract source. It is OUT of the audit subject and is not part of any fingerprint.

**The freeze contract for every later sweep:** before reproducing any lead, each sweep phase
(389–396) asserts `git diff a8b702a7 -- contracts/` is empty. If a fix is ever applied, it is a
separate USER-hand-reviewed gated boundary, after which the subject re-freezes at a new pin.

---

## 2. The audit-delta surface (`git diff --stat 77580320 a8b702a7 -- contracts/`)

The surface this milestone audits — the post-v62 contract change set that landed on `main` without a
formal audit-milestone close. **40 files changed, +4322 / −3489.**

```
 contracts/BurnieCoin.sol                           |   53 +-
 contracts/BurnieCoinflip.sol                       |  322 +++---
 contracts/DegenerusAdmin.sol                       |  177 ++--
 contracts/DegenerusAffiliate.sol                   |  156 ++-
 contracts/DegenerusDeityPass.sol                   |   46 +-
 contracts/DegenerusGame.sol                        | 1038 ++++++--------------
 contracts/DegenerusJackpots.sol                    |  216 ++--
 contracts/DegenerusQuests.sol                      |  551 ++++++-----
 contracts/DegenerusStonk.sol                       |   28 +-
 contracts/DegenerusTraitUtils.sol                  |    4 +-
 contracts/DegenerusVault.sol                       |  159 +--
 contracts/DeityBoonViewer.sol                      |    5 +-
 contracts/GNRUS.sol                                |  163 +--
 contracts/Icons32Data.sol                          |    2 +-
 contracts/StakedDegenerusStonk.sol                 |  324 ++++--
 contracts/WrappedWrappedXRP.sol                    |   26 +-
 contracts/interfaces/IBurnieCoinflip.sol           |   21 +-
 contracts/interfaces/IDegenerusAffiliate.sol       |    8 +-
 contracts/interfaces/IDegenerusGame.sol            |  172 ++--
 contracts/interfaces/IDegenerusGameModules.sol     |   96 +-
 contracts/interfaces/IDegenerusQuests.sol          |    6 +
 contracts/interfaces/IVaultCoin.sol                |    4 -
 contracts/libraries/BitPackingLib.sol              |    4 -
 contracts/libraries/EntropyLib.sol                 |   22 +-
 contracts/libraries/JackpotBucketLib.sol           |   26 +-
 contracts/libraries/PriceLookupLib.sol             |   25 +-
 contracts/modules/DegenerusGameAdvanceModule.sol   |  244 ++---
 contracts/modules/DegenerusGameBingoModule.sol     |   58 +-
 contracts/modules/DegenerusGameBoonModule.sol      |   17 +-
 contracts/modules/DegenerusGameDecimatorModule.sol |  349 ++++---
 .../modules/DegenerusGameDegeneretteModule.sol     |  435 ++++++--
 contracts/modules/DegenerusGameGameOverModule.sol  |    8 +-
 contracts/modules/DegenerusGameJackpotModule.sol   |  794 +++++++--------
 contracts/modules/DegenerusGameLootboxModule.sol   |  744 +++++++++-----
 contracts/modules/DegenerusGameMintModule.sol      |  545 +++++++---
 contracts/modules/DegenerusGameMintStreakUtils.sol |   99 +-
 contracts/modules/DegenerusGamePayoutUtils.sol     |    4 +-
 contracts/modules/DegenerusGameWhaleModule.sol     |  164 ++--
 contracts/modules/GameAfkingModule.sol             |  347 ++++---
 contracts/storage/DegenerusGameStorage.sol         |  349 +++++--
 40 files changed, 4322 insertions(+), 3489 deletions(-)
```

---

## 3. Per-family characterization (the sweep planners' slices)

The delta is dominated by a few overlapping change families. Each file below is tagged with the
family(ies) the v63 plan's sweep phases own. (Families per `AUDIT-V63-PLAN.md` §1: storage packing ·
BURNIE emission rework · gas-identity refactors · new permissionless/keeper entrypoints · reward
rebalances · redemption rework.)

### A. Storage packing (the full post-v62 packing phase) — owner: 389 PACKING-IDENTITY

The single largest mechanical family — slot folds/repacks that shifted layout REGION-DEPENDENTLY (not
a uniform −1; see 388-01 §5). The slot-drift risk class ([[storage-packing-breaks-slot-hardcoded-tests]])
is exactly why Plan 01 re-derived the authoritative layout and reconciled every slot-hardcoded harness.

- `contracts/storage/DegenerusGameStorage.sol` (+349) — the Game's delegatecall-shared base: tail
  compaction (max slot 63→59), the consolidated tail packs (`levelDgnrsPacked`@26, `deityBoonPacked`@36,
  `lootboxEvCapPacked`@40, `bingoFirsts`@53, the narrowed `DecClaimRound` 1-slot struct), and the
  `totalFlipReversals`(u64)/`lastVrfProcessedTimestamp`(u48) co-residency at slot 5.
- `contracts/StakedDegenerusStonk.sol` (+324) — slot-0 pack
  (`_totalSupply`/`_pendingRedemptionEthValue`/`_pendingResolveDay`, net −3) + `poolBalances` uint128[5]
  (overlaps redemption-rework family — see E).
- `contracts/BurnieCoinflip.sol` (+322) — `coinflipStakePacked`@0 (2-days/slot 128-bit lanes) +
  `coinflipDayResultPacked`@1 (32-days/slot 8-bit 3-state lanes) + the `sdgnrsAutoRebuyArmed`@4 bool
  (overlaps BURNIE-emission family — see B).
- `contracts/DegenerusAdmin.sol` (+177) — the `voterRecords`@5 / `feedVoterRecords`@10 votes+weight
  struct folds (ABI getters preserved).
- `contracts/libraries/BitPackingLib.sol` (−4), `contracts/libraries/JackpotBucketLib.sol`,
  `contracts/libraries/PriceLookupLib.sol`, `contracts/libraries/EntropyLib.sol` — packing-helper /
  gas-identity library churn (see C; EntropyLib overlaps RNG-freeze).

### B. BURNIE emission rework — owner: 392 BURNIE / coinflip-seed family

The 200k/day×20d coinflip seed schedule replacing the former 2M+2M lumps, the sDGNRS day-20 auto-rebuy
latch, the Degenerette survival flip, and `claimCoinflipCarry`.

- `contracts/BurnieCoinflip.sol` (+322) — coinflip seed stakes, day-result packing, the `sdgnrsAutoRebuyArmed`
  latch (also family A).
- `contracts/BurnieCoin.sol` (+53), `contracts/interfaces/IBurnieCoinflip.sol` (+21) — emission/mint
  surface + interface.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` (+435) — Degenerette survival flip + the
  composite activity-score award model (`s = A + 2*H`); BURNIE flip-credit draws (overlaps reward
  rebalances — see F).

### C. Gas-identity refactors (behavior-identical bytecode/gas reductions) — owner: 389 PACKING-IDENTITY

The de-dup / nibble-table / hash-migration / Game-size-reclaim churn that drove the Game bytecode down
(24,089 → ~19,001) while preserving RNG byte-image and behavior. The headline `DegenerusGame.sol`
−~1038 (net shrink, the de-view/de-dup reclaim) lives here.

- `contracts/DegenerusGame.sol` (+1038 col, net large shrink) — the dispatcher de-dup + getter
  consolidation + Game-size reclaim (also touches new entrypoints — see D).
- `contracts/interfaces/IDegenerusGame.sol` (+172), `contracts/interfaces/IDegenerusGameModules.sol`
  (+96) — interface realignment for the consolidated dispatch.
- `contracts/libraries/EntropyLib.sol` (+22) — hash1/hash2 RNG-byte-identical migration (RNG-freeze
  spine — verify byte-image preservation).
- `contracts/modules/DegenerusGameMintStreakUtils.sol` (+99),
  `contracts/modules/DegenerusGamePayoutUtils.sol`, `contracts/DegenerusTraitUtils.sol`,
  `contracts/Icons32Data.sol`, `contracts/DeityBoonViewer.sol` — utility/data gas-identity churn.

### D. New permissionless / keeper entrypoints — owner: 393 PERMISSIONLESS-ENTRYPOINTS

The new permissionless economically-incentivized entrypoints (e.g. `openBoxes`, keeper-bounty paths,
the permissionless lootbox/decimator-claim surface).

- `contracts/modules/DegenerusGameLootboxModule.sol` (+744) — the lootbox queue/materialize +
  permissionless open + Degenerette lootbox spins + EV-cap-at-open (overlaps reward rebalances — F).
- `contracts/modules/DegenerusGameDecimatorModule.sol` (+349) — terminal-decimator offset keyed at
  `[lvl+1]` (DEC-ALIAS fix) + uint32 claim-seed draw + bucket bounty.
- `contracts/modules/DegenerusGameJackpotModule.sol` (+794) — the JackpotModule delta-fold (4-pool
  consolidation/skim/jackpot transfers) + final-day routing.
- `contracts/modules/GameAfkingModule.sol` (+347) — afking-as-payment, the cancel/auto-claim
  `affiliateBase` drain, pass-eviction inclusive boundary.
- `contracts/modules/DegenerusGameWhaleModule.sol` (+164),
  `contracts/modules/DegenerusGameBingoModule.sol` (+58),
  `contracts/modules/DegenerusGameGameOverModule.sol` (+8) — whale-pass O(1) / bingo color-completion /
  game-over batch.

### E. Redemption rework (solvency spine) — owner: 390 SOLVENCY-SPINE

The sDGNRS redemption rework — the CEI / stETH-before-ETH ordering (V62-03 class), the new
direct/lootbox/dust-forfeit split legs, and the GAME-only `receive()`.

- `contracts/StakedDegenerusStonk.sol` (+324) — the redemption submit/resolve/claim lifecycle + the
  split legs + the dust-forfeit (also family A).
- `contracts/DegenerusVault.sol` (+159) — vault interaction with the redemption/claim surface.
- `contracts/modules/DegenerusGameMintModule.sol` (+545) — mint/redemption credit path + the
  ticket-mint primitive (overlaps reward rebalances — F).
- `contracts/interfaces/IVaultCoin.sol` (−4) — interface trim.

### F. Reward rebalances (reward game-theory) — owner: 394 REWARD-GAME-THEORY

The reward-split / EV-multiplier / ticket-distribution rebalances and the quest/affiliate reward
game-theory (the milestone's headline game-theory surface; anchor `PAPER-REWARD-CHANGES-BRIEF.md`).

- `contracts/DegenerusQuests.sol` (+551) — quest streak halve/uncap, unified activity score, quest
  reward draws.
- `contracts/DegenerusAffiliate.sol` (+156), `contracts/interfaces/IDegenerusAffiliate.sol` (+8) —
  affiliate score/distribution + the single-step claim.
- `contracts/DegenerusJackpots.sol` (+216) — jackpot reward distribution + final-day `Pool.Reward`
  deletion.
- `contracts/modules/DegenerusGameAdvanceModule.sol` (+244) — the advance/reward-settlement path (RNG
  advance — VRF-path spine; the carried bucket-A invariants probe this surface).
- `contracts/modules/DegenerusGameBoonModule.sol` (+17),
  `contracts/modules/DegenerusGameMintModule.sol` (+545, also family E) — boon/reward application.
- `contracts/DegenerusStonk.sol` (+28), `contracts/DegenerusDeityPass.sol` (+46),
  `contracts/GNRUS.sol` (+163), `contracts/WrappedWrappedXRP.sol` (+26),
  `contracts/interfaces/IDegenerusQuests.sol` (+6) — supporting token/governance/reward surface.

> Family tags are guidance for the sweep planners, not hard partitions — several files (notably
> `StakedDegenerusStonk.sol`, `BurnieCoinflip.sol`, `DegenerusGameMintModule.sol`,
> `DegenerusGameLootboxModule.sol`) carry more than one family and are owned jointly. The authoritative
> per-lead routing lives in the 388-02 intake ledger (45 leads across 389:9 / 390:7 / 391:5 / 392:20 /
> 393:4 / 394:0).

---

## 4. Assertions (FND-01 acceptance)

- [x] `git rev-parse a8b702a7:contracts` = `2934d3d8987a09c5f073549a0cb499f6c5f28620` recorded (the byte-freeze tree-hash pin).
- [x] deterministic content sha256 `0c684378df8d12f339af54e39de7df55971643f69e6b68f02332e918c20d15b3` recorded.
- [x] `git rev-parse HEAD:contracts` == `git rev-parse a8b702a7:contracts` (working tree byte-identical to subject).
- [x] `git diff a8b702a7 -- contracts/` is EMPTY (asserted).
- [x] `git status --porcelain contracts/` is EMPTY (no contract-source dirt; ContractAddresses not regenerated).
- [x] `git diff --stat 77580320 a8b702a7 -- contracts/` recorded (40 files, +4322/−3489) with a per-family characterization.
- [x] `PLAYER-PURCHASE-REWARDS.html` noted OUT of scope (player-facing doc, not a contract).
