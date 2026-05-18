---
artifact: ADVERSARIAL-CONTRACT-AUDITOR
phase: 296-cross-surface-adversarial-sweep-sweep
plan: 01
milestone: v42.0
skill: contract-auditor
adversarial_pass_pattern: SEQUENTIAL_MAIN_CONTEXT
audit_subject_surfaces: [MINTCLN, HRROLL, DPNERF, RETRY_LOOTBOX_RNG]
generated_at: 2026-05-18
---

# Phase 296 Adversarial Pass — /contract-auditor

Pass over the 13 charged hypotheses + 1 user-added beyond-charge surface (`retryLootboxRng()`).
Persona: adversarial security researcher with 1000-ETH budget, EVM internals expertise, MEV/VRF/economic-attack focus.

---

## Hypothesis (i) — 3-input hash determinism break

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `contracts/modules/DegenerusGameMintModule.sol:426-429` + `:763-766` — `baseKey` constructed at both `processFutureTicketBatch` (inline path) and `_processOneTicketEntry` (split path). Layout: `(lvl<<224) | (queueIdx<<192) | (uint160(player)<<32) | owed`. Bit ranges non-overlapping.
- `_raritySymbolBatch` seed at `:563-565`: `keccak256(abi.encode(baseKey, entropyWord, groupIdx))`. groupIdx = `i >> 4` within the local LCG loop.
- Within a single drain on the same `(rk, player)` slot, `owed` monotonically shrinks across batches (`remainingOwed = owed - take` at `:478-481` and `:803-805`), so `baseKey` low 32 bits change between successive `_raritySymbolBatch` invocations — mirroring the role `ownedSalt` played at v41 close.
- Cross-call separation across distinct slots is preserved by `(lvl, queueIdx, player)` upper-bit distinctness.
- `entropy` is read from `lootboxRngWordByIndex[index - 1]` at `:686`. Within one VRF cycle the queue at any `rk` can be drained at most once (`delete ticketQueue[rk]` runs upon completion); new pushes after the delete do not advance the entropy register until the next VRF cycle delivers a new word. Cross-lifetime same-slot collisions across different cycles use different entropies → no seed collision.

**Notes:**
- Considered the zero-owed → rolled-to-1 branch in `_processOneTicketEntry` (`:768-779`): `baseKey` is constructed with `owed == 0` BEFORE `_resolveZeroOwedRemainder` may roll the rem and set local `owed = 1`. The subsequent `_raritySymbolBatch` call at `:793` therefore carries stale low-32-bit `owed == 0`. Per `290-01-DESIGN-INTENT-TRACE.md` §(ii) note 2: only a single-trait emission follows this branch, `advance = (remainingOwed == 0)` always evaluates true after, so the outer loop advances to a fresh slot. Cross-lifetime same-slot collisions blocked by VRF-cycle gating (different cycles → different entropy → different seed).
- Considered queueIdx overflow into adjacent bit ranges: `ticketCursor` is `uint32`; max value 2³² − 1 fits exactly in the reserved 32-bit slot at positions 192-223.
- Considered cross-position same-LCG-group collisions within `_raritySymbolBatch`: seed varies with `groupIdx`, and within a group the LCG iterates `s = s * LCG_MULT + 1` → per-position outputs pairwise-distinct within a group.

---

## Hypothesis (ii) — `owed`-in-baseKey griefing on shape collision

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- Bit-range layout at `contracts/modules/DegenerusGameMintModule.sol:424-429` + `:763-766`: lvl (uint24, bits 224-247 within reserved 224-255), queueIdx (uint32, bits 192-223), player (uint160, bits 32-191), owed (uint32, bits 0-31). Reserved ranges are pairwise non-overlapping; bit-packing is injective.
- `queueIdx` source is `ticketCursor` (uint32 in storage); parameter type at `:759` is `uint256` but value never exceeds uint32 max because callers pass `uint256 idx` initialized from `uint32 ticketCursor` at `:404` and `:672`.
- `uint256(uint160(player))` zero-extends the 160-bit address — no high-bit leakage into queueIdx (bits 192-223) or lvl (bits 224-255) ranges.
- Zero-owed branch produces `baseKey` with low 32 bits = 0; upper bits remain fully distinctive for the `(lvl, queueIdx, player)` triple. A second invocation with `owed > 0` at the same triple produces a different baseKey.

**Notes:**
- For two distinct `(lvl, queueIdx, player, owed)` tuples to collide on `baseKey`, the bit-packing would need to be non-injective — mathematically impossible under non-overlapping reserved ranges.
- Considered craftable addresses: address is 160 bits, occupying exactly bits 32-191. No addressing strategy injects address bits into bits 192+ (the `<< 32` shift is fixed at construction sites).
- Considered ticketCursor reaching the 32-bit reserved width: writes-budget per batch is bounded (`WRITES_BUDGET_SAFE`); reaching 2³² queue entries on a single `rk` is not practically attainable, and even if it were, the cursor still fits the reserved 32-bit field.

---

## Hypothesis (iii) — `TraitsGenerated` topic-hash break parsing ambiguity

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- v41 canonical signature `TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)` → topic-0 `0x5e96bf2d…`; v42 canonical signature `TraitsGenerated(address,uint256,uint32)` → topic-0 `0x279edf1c…`. Mutually exclusive via keccak avalanche.
- Two emit sites at `contracts/modules/DegenerusGameMintModule.sol:471` + `:794`; event declaration in `DegenerusGameStorage.sol` (3-field shape at v42 close). LOG opcode count drops from LOG3 → LOG2 with payload narrowing.
- No in-contract reader of `TraitsGenerated` exists (emission for off-chain indexers only); grep of `contracts/` finds no internal consumer.
- Pre-launch posture per D-42N-EVT-BREAK-01 inheriting D-40N-EVT-BREAK-01 verbatim: no live indexer state to preserve. Indexer rebuild is a documented forward-handoff.

**Notes:**
- Considered fixed-buffer parsers: payload size shifts from 128 B LOGDATA + 3 topics to 64 B LOGDATA + 2 topics. A parser hardcoded for v41 size would fail — no live indexer exists; post-launch indexers built directly against v42 ABI.
- Considered partial-topic / event-name-string decoders: topic-0 is the only reliable correlation key. A decoder using event names (not topic-hash) would need the new ABI to look up the right hash anyway.

---

## Hypothesis (iv) — ×1.5 leader bonus whale-coordination / wash-trading MEV

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- `_rollHeroSymbol` at `contracts/modules/DegenerusGameJackpotModule.sol:1639-1700` computes `leaderBonus = maxAmount / 2`, `effectiveTotal = total + leaderBonus`, `pick = uint64(uint256(keccak256(abi.encode(entropy, day))) % effectiveTotal)`. Entropy = raw `randWord` per D-42N-BONUS-ENTROPY-01.
- Wager-write site at `contracts/modules/DegenerusGameDegeneretteModule.sol:484-501` writes `dailyHeroWagers[day][q]` during `_placeDegeneretteBet`. Critical gate at `:450-452`: `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();` — bets revert as soon as the current VRF index has a fulfilled word.
- `entropy` in the `_rollHeroSymbol` keccak is delivered by VRF; unknowable at wager-time. No `randomWord` derivative is observable in the mempool prior to VRF coordinator submission.

**Notes:**
- Considered final-block leader vault: bet path closes at the moment `lootboxRngWordByIndex[index] != 0`, same tx that delivers the VRF word also forbids new bets for that index. A bet that lands BEFORE the VRF callback in the same block is informationally symmetric (bettor cannot observe the random word at submission time).
- Considered alternating leader on adjacent days: `_rollHeroSymbol` reads `dailyHeroWagers[day][q]` for `day == dailyIdx`. Cross-day reads do not influence current day's pick.
- Considered wash-trading via account rotation: wager state requires real ETH commitment (no rebate path in jackpot resolution). Wash-trading costs are proportional.

---

## Hypothesis (v) — No-floor sybil dilution attack

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `wagerUnit = totalBet / 1e12` at `contracts/modules/DegenerusGameDegeneretteModule.sol:489` — smallest payable bet contributing one wager-unit costs 10¹² wei = 1 µETH.
- Per-slot saturation at L494-495: `if (updated > 0xFFFFFFFF) updated = 0xFFFFFFFF` — slot caps at 2³² − 1 wager-units. 32-slot full coverage costs 32 × 10¹² wei = 0.032 ETH at-risk minimum.
- At realistic organic volumes (single 1 mETH bet = 10⁹ wager-units), the attacker's 32-unit dilution payload is 32/(10⁹ + 32) ≈ 3.2 × 10⁻⁸ of effectiveTotal — economically negligible.
- No rebate path: `_rollHeroSymbol` does not refund wagerers.

**Notes:**
- Considered amplification via `traitBurnTicket`: sybil bets do not push to `traitBurnTicket`; they write only `dailyHeroWagers`.
- Considered per-slot saturation as a side-effect: cap at 2³² − 1 wager-units (~4.3 ETH at 1e12 scale) limits concentration. Bounded griefing surface, not exploitable for extraction.

---

## Hypothesis (vi) — Symbol-roll VRF bit-collision with existing entropy consumers

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- `_rollHeroSymbol` keccak at `contracts/modules/DegenerusGameJackpotModule.sol:1684`: `pick = uint64(uint256(keccak256(abi.encode(entropy, day))) % effectiveTotal)`. Output domain is the 256-bit keccak codomain.
- `_applyHeroOverride` callsite at `:2001` (`_rollWinningTraits`): `_applyHeroOverride(traits, r, randWord)`. Third argument is raw `randWord` (heroEntropy = randWord).
- Existing bit-slice consumers read raw `randWord` directly (jackpot-path bits[0..12]; lootbox-Bernoulli bits[152..167]; jackpot-Bernoulli bits[200..215]) or read `r = randWord` / `r = keccak256(abi.encodePacked(randWord, BONUS_TRAITS_TAG))` (color-sample at `_applyHeroOverride:1614-1620`).
- Domain-separation idiom: HRROLL uses `abi.encode` (32-byte aligned, type-tagged); bonus-tag uses `abi.encodePacked`. Different byte sequences; outputs in disjoint pseudorandom subspaces.

**Notes:**
- Considered keccak-avalanche orthogonality: keccak-256 output bits are statistically independent of input bit-slices.
- Considered `dailyIdx` ambiguity: `_unlockRng` at `DegenerusGameAdvanceModule.sol:1729-1736` is the sole writer; set once per VRF cycle before jackpot resolution consumes the wager pool.

---

## Hypothesis (vii) — Gas regression DOS

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- `_rollHeroSymbol` body at `contracts/modules/DegenerusGameJackpotModule.sol:1639-1700`: 4 × SLOAD; two 32-iteration loops with fixed bounds; one keccak; one MOD; one DIV. No unbounded computation; no user-controllable loop bound.
- Theoretical worst-case +431 gas per call per `292-01-MEASUREMENT.md` — under D-42N-GAS-01 soft threshold +500.
- Memory: `uint32[32] memory weights` = 1024 bytes = 32 memory slots. Single allocation; no growth surface.

**Notes:**
- Considered bonus-day double-invocation: worst-case 2 × +431 = +862 gas, within budget.
- Considered writes-budget-bounded caller chain: `_rollWinningTraits` invoked at most twice per jackpot resolution (regular + optional bonus). Not embedded in adversary-controlled iteration.

---

## Hypothesis (viii) — Intentional EV reduction secondary attacks

**Disposition:** ACCEPTED_DESIGN

**Evidence:**
- `_randTraitTicket` at `:1731-1737` and `_awardDailyCoinToTraitWinners` at `:1867-1874` encode the gold/commons branch. Per D-42N-DEITY-EV-01 the gold-tier deity virtual entries are locked to flat 1.
- EV reduction is intentional and user-disposition-locked. Deity-pass holders see strictly lower expected returns on gold-tier; commons-tier EV is UNCHANGED.

**Notes:**
- Secondary-market behavioral pivots (deity holders bidding on commons; pass price re-equilibration) are economic-equilibrium phenomena, not code-vulnerability surfaces.
- Considered temporal arbitrage on pass acquisition: `deityBySymbol` is read at jackpot-resolution time; the pass-holder pays prevailing price and earns prevailing nerfed EV. Observable design property, not extraction.
- Considered downstream module interactions (`DegenerusGameBoonModule`, `DegenerusGameWhaleModule`): the gold-tier EV nerf does not invalidate boon or whale-tier logic.

---

## Hypothesis (ix) — ETH↔BURNIE both-paths differential behavior

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- ETH path at `_randTraitTicket:1707-1763` produces N winners via single-bucket sampler `idx = keccak256(abi.encode(randomWord, trait, salt, i)) % effectiveLen` (`:1749-1751`); sentinel pair at `:1755-1757`.
- BURNIE path at `_awardDailyCoinToTraitWinners:1822-1913` produces up to `cap` winners via multi-bucket sampler iterating over `lvlPrime` and `trait_i = traitIds[i % 4]`; per-pull `idx = keccak256(abi.encode(randomWord, trait_i, lvlPrime, i)) % effectiveLen` (`:1883-1885`); sentinel pair at `:1888-1893`.
- Gold-tier branch identical: `virtualCount = 1` on gold; `max(len/50, 2)` on commons. Identical arithmetic.

**Notes:**
- Considered event-emission timing as an oracle: `JackpotBurnieWin` emitted after winner determination is final. Observation-after-resolution, not extraction-during.
- Considered `coinBudget` vs `ethPool` flow asymmetry: independent prize-currency economies; gold-tier nerf applies identically to both.
- Considered sampler asymmetry as attack vector: BURNIE's `lvlPrime` is derived from `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i))` (`:1856-1858`) — independent of mutable state. No manipulation surface.

---

## Hypothesis (x) — BURNIE inline-duplicate vs ETH differential

**Disposition:** SAFE_BY_DESIGN

**Evidence:**
- ETH path `:1729-1738` and BURNIE path `:1862-1874`: textually parallel gold-tier branches. `deity = deityBySymbol[fullSymId]` (ETH) vs `deity = deityCache[traitIdx]` (BURNIE, cached at `:1839-1847`); identical conditional shape.
- Identical `virtualCount = 1` on gold; identical `virtualCount = max(len/50, 2)` on commons.
- Identical `effectiveLen = len + virtualCount` at `:1741` (ETH) and `:1875` (BURNIE).
- Sentinel-pair invariants algebraically equivalent: `idx < len` → holder; `idx >= len` → deity with `idx = type(uint256).max`. Both paths.
- Per `294-02-SUMMARY.md`: commit `38319463` was authored specifically to close the BURNIE-path coverage gap exposed by Phase 294 Plan 02 verification (D-294-BURNIE-INLINE-01).

**Notes:**
- Considered `coinBudget` underflow: early-exit at `:1829` if `coinBudget == 0`; caps at `cap = min(DAILY_COIN_MAX_WINNERS, coinBudget)` at `:1830-1831`. No underflow.
- Considered `lvlPrime` boundary effects: range `= maxLevel - minLevel + 1`; caller-side guards ensure `maxLevel >= minLevel`.
- The `deityCache` at `:1839-1847` content is byte-identical to a fresh per-pull read (`deityBySymbol` not mutated during resolution).

---

## Hypothesis (xi) — DPNERF callsites 1+2 production-path coverage gap

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- `_randTraitTicket` is a single function-body at `contracts/modules/DegenerusGameJackpotModule.sol:1707-1763`. Gold-tier nerf landed inside the function body at `:1731-1737`. All callers route through the same body — no inline-copy at any callsite.
- Callsites: `:698` (callsite 1, `_runEarlyBirdLootboxJackpot`); `:988` (callsite 2, `_distributeTicketsToBucket`); `:1296` (callsite 3, TST-DPNERF covered); `:1399` (callsite 4, TST-DPNERF covered).
- Single function-body is the SOLE delivery mechanism. All 4 callers inherit by construction.

**Notes:**
- Considered callsite 1 (early-bird lootbox jackpot): per-trait bucket size influences `effectiveLen` arithmetically but NOT the gold-tier branch condition (purely a bit-test on the trait byte). Nerf semantics are bucket-size-independent at the branch level.
- Considered callsite 2 (`_distributeTicketsToBucket`) with 3 upstream paths: each upstream sets `numWinners` and `salt` parameters but doesn't alter `traitBurnTicket_` content at the moment of `_randTraitTicket` call.
- Considered carryover-ticket level-crossing: tickets from level N enter level N+1's `traitBurnTicket` via the carryover bucket-distribution path. At `_randTraitTicket` call time, `len` reflects the current bucket state for the level being processed. No "un-nerfed gold EV" leakage path.
- The coverage gap per D-295-CALLSITE-SCOPE-01 is regression-fixture coverage; behavior at callsites 1+2 is identical to callsites 3+4 by construction.

---

## Hypothesis (xii) — MINTCLN owed-in-baseKey vs v41 owed-salt

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- v40 collision class (F-41-01): within-day multi-call drains where successive `_raritySymbolBatch` invocations hashed identical seeds when `owed > writesBudget / 2`.
- v41 Phase 281 fix: added 6th positional `ownedSalt = owed_at_call_entry`. Guaranteed pairwise-distinct seeds because `owed_at_call_entry` shrinks per emit.
- v42 fix (MINTCLN-01/02/03): collapses ownedSalt into `baseKey` low 32 bits. When outer loop re-enters same `(rk, player)` slot with smaller `owed`, baseKey itself changes between successive invocations.
- Within-drain mechanism: `remainingOwed = owed - take` at `:478-481` (inline path) and `:803-805` (split path).

**Notes:**
- Considered v41 owed-salt invariant under v42 packing: algebraic property `seed(batch_k) ≠ seed(batch_k+1)` preserved because `owed_k ≠ owed_k+1` AND `owed_k` is exactly the low 32 bits of `baseKey_k`.
- Considered zero-owed → rolled-to-1 edge case (per `290-01-DESIGN-INTENT-TRACE.md` §(ii) note 2): stale `owed = 0` in low 32 bits of baseKey during the rolled-to-1 emission. Single-emit branch with `advance = true` after. Cross-lifetime same-slot collisions blocked by VRF-cycle gating (different entropies across cycles).
- Considered `_rollRemainder` consumers at `:443` + `:489` + `:746` + `:824`: same baseKey distinctness mechanism applies; pairwise-distinct rollEntropy across batches.

---

## Hypothesis (xiii) — HRROLL leader-bonus + rngLocked window interaction

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE

**Evidence:**
- Wager-write site at `DegenerusGameDegeneretteModule.sol:484-501` preceded by RNG-readiness gate at `:450-452`: `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();`. Bets revert as soon as the current VRF index has a fulfilled word.
- `dailyIdx` single-writer invariant per D-288-FIX-SHAPE-01: `_unlockRng(uint32 day)` at `DegenerusGameAdvanceModule.sol:1729-1736` is the only mutator. `dailyIdx = day` write at `:1730` precedes `rngLockedFlag = false` at `:1731`.
- `_rollHeroSymbol` at `:1639-1700` reads `dailyHeroWagers[day][q]` where `day` is passed from `_applyHeroOverride` at `:1609` as current `dailyIdx`. At jackpot-resolution, `dailyIdx` carries the day-being-resolved.
- Pass-1 leader tracking iterates cached `weights[]` snapshot; pass-2 cumulative walk reads same cache. Snapshot is taken once at function entry; not re-read during cumulative walk.

**Notes:**
- Considered rngLocked window state machine: `rngLockedFlag = true` at `:1634` (VRF request); `rngLockedFlag = false` at `:1690`/`:1731` (post-state-reset). The L452 readiness gate independently prevents bets for the in-flight index.
- Considered cross-day boundary races: `_simulatedDayIndex()` at `:486` is forward-looking; bets land in appropriate day's pool. The next VRF cycle consumes the pool when `dailyIdx` advances to match.
- Backward-trace confirmed: `heroEntropy` at `_rollHeroSymbol` sourced from `_applyHeroOverride` → `_rollWinningTraits` → raw `randWord` (VRF callback). No player-controllable input feeds randWord derivation.

---

## Hypothesis (xiv) — `retryLootboxRng()` beyond-charge surface (user-added during sweep)

**Disposition:** SAFE_BY_DESIGN with MEDIUM observation on docstring/scope boundary

**Function purpose:** When `requestLootboxRng()` has committed a mid-day buffer swap (LR_MID_DAY=1) and VRF callback has not delivered within 6 hours, allow anyone to re-fire a VRF request that lands in the SAME pre-advanced bucket as the original mid-day request. Stalled requestId auto-rejected by requestId-match check.

**Evidence:**
- Function body at `contracts/modules/DegenerusGameAdvanceModule.sol:1132-1155`.
- State preservation verified:
  - `requestLootboxRng` advances LR_INDEX at `:1113-1117`; `retryLootboxRng` does NOT. Pre-advanced bucket preserved.
  - `requestLootboxRng` swaps ticket buffer + sets LR_MID_DAY=1 at `:1094-1097`; `retryLootboxRng` does NOT re-swap.
  - `requestLootboxRng` clears LR_PENDING_ETH/BURNIE at `:1118-1119`; `retryLootboxRng` does NOT (already cleared by original).
- Stalled-callback auto-rejection: after retry, `vrfRequestId = id_new`. Old `requestId_old` callback at `rawFulfillRandomWords:1750` (`if (requestId != vrfRequestId || rngWordCurrent != 0) return;`) silently drops.
- Bucket placement on retry: `rawFulfillRandomWords` mid-day branch at `:1758-1765` writes to `lootboxRngWordByIndex[LR_INDEX − 1]`. Since LR_INDEX unchanged by retry, this is the original mid-day's intended bucket.
- Permissionless griefing surface bounded: requires LR_MID_DAY=1, rngRequestTime > 0, elapsed ≥ 6h, LINK ≥ 40 ether. After successful retry, `rngRequestTime` resets to now → next retry gated 6h later.

**Notes:**
- **Observation A (INFO):** External-call-then-state-update ordering. The `vrfCoordinator.requestRandomWords(...)` external call at `:1142` happens BEFORE `vrfRequestId = id` and `rngRequestTime = now` at `:1153-1154`. If the VRF coordinator were malicious and re-entered synchronously, at the re-entry point `vrfRequestId`/`rngRequestTime` still carry pre-call values → guards pass → another `requestRandomWords` fires → LINK loop until subscription drains. This is THE SAME PATTERN as `requestLootboxRng` (`:1101` external call before `:1120-1122` state updates), so it's an established trust-model assumption. Audit-baseline trust model permits this. INFO under current model.
- **Observation B (INFO):** No `rngLockedFlag` check. `requestLootboxRng` reverts on `rngLockedFlag` (`:1044`); `retryLootboxRng` does NOT. If daily flow has taken over the in-flight VRF (via `_finalizeRngRequest`'s `isRetry` shortcut at `:1615-1617`), `retryLootboxRng` re-fires the in-flight request — overwriting the daily-flow's `vrfRequestId` with a new id. The daily-flow's pending callback then drops at `:1750`. When the retry's callback arrives with `rngLockedFlag = true`, `rawFulfillRandomWords` enters the DAILY branch (`:1755-1757`) and stores the word as `rngWordCurrent` for daily processing. The retry's word fills both purposes. Functionally works as an implicit recovery path, but the retry silently behaves differently depending on `rngLockedFlag` state. Docstring describes only the mid-day-only case.

**Description (Observation C — MEDIUM):**
Stuck-state when daily-takeover completes while LR_MID_DAY=1. Scenario: (1) `requestLootboxRng` fires at T0 → LR_MID_DAY=1, rngRequestTime=T0, vrfRequestId=id_M, LR_INDEX advanced. (2) Mid-day stalls. (3) Daily-RNG cycle triggered. `_finalizeRngRequest` sees isRetry=true, skips LR_INDEX advance, overwrites vrfRequestId=id_D, rngLockedFlag=true. (4) Daily VRF delivers id_D. `_finalizeLootboxRng` writes `lootboxRngWordByIndex[X] = word` (because LR_INDEX still X+1). `_unlockRng` clears vrfRequestId=0, rngRequestTime=0, rngLockedFlag=false. (5) Final state: LR_MID_DAY=1, rngRequestTime=0, mid-day bucket filled. The mid-day path in advanceGame (`:205+`) DOES recover by processing the buffer (word is now non-zero). But `retryLootboxRng` is now USELESS for unsticking: it requires `rngRequestTime != 0`, which is 0 after `_unlockRng`. If advanceGame is not called for an extended period, the buffer sits with a valid word but unprocessed tickets, and the docstring's framing ("retry a stalled mid-day request") suggests retry should help — it cannot.

**Severity estimate:** MEDIUM. Pre-launch posture means no live impact. Liveness-class, not value-extraction. Self-healing via the next advanceGame call (bounty-incentivized).

**Suggested remediation (descriptive only):**
Two options for user review:
- (a) Document explicitly that `retryLootboxRng` is the EARLY mid-day-stall recovery (6h) and the daily-flow's `isRetry` shortcut is the LATE recovery (12h + day-rollover). They're complementary, not redundant.
- (b) Extend `retryLootboxRng`'s guard to also accept the case `LR_MID_DAY=1 && rngRequestTime == 0` (no in-flight VRF) by re-firing a fresh VRF request for the pre-advanced bucket. This would close the small window where LR_MID_DAY=1 persists after `_unlockRng` zeroed `rngRequestTime`.

---

## Cross-cutting note

The v42 MINTCLN simplification (4-input keccak → 3-input keccak with owed embedded in baseKey) preserves the v41 F-41-01 fix's algebraic invariant exactly. The HRROLL ×1.5 leader-bonus introduces a new RNG-consumer surface that is structurally orthogonal to existing bit-slice consumers (keccak output domain vs raw randWord bit-slice domain — non-collision by hash-function design, not by probabilistic argument). The DPNERF gold-tier nerf is a single function-body change in `_randTraitTicket` (+ a textually parallel branch in `_awardDailyCoinToTraitWinners` via commit `38319463`); both sites carry identical arithmetic.

The single edge case worth highlighting on the 13 charged hypotheses is the zero-owed → rolled-to-1 branch (covered by within-drain advance + cross-lifetime VRF-cycle gating).

The added beyond-charge surface (`retryLootboxRng`) is well-bounded and consistent with the surrounding patterns; the MEDIUM observation in (C) is documentation/scope-shape, not value-extraction. Twelve of the thirteen charged hypotheses landed SAFE-variant; one (viii) landed ACCEPTED_DESIGN. Hypothesis (xiv) the user-added surface returned SAFE_BY_DESIGN with one MEDIUM observation surfaced for user review.

Zero CRITICAL or HIGH findings.
