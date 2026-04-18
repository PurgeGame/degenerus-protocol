---
phase: 230-delta-extraction-scope-map
plan: 230-02
type: addendum
status: complete
date: 2026-04-17
addendum_to: 230-01-DELTA-MAP.md
---

# Phase 230 Delta Addendum — Post-Phase-230 RNG Hardening Commits

## Purpose

Phase 230's `230-01-DELTA-MAP.md` catalogued the 10-commit delta from v27.0 baseline `14cb45e1` to the 2026-04-17 morning HEAD. Two additional contract commits landed later the same day, both hardening randomness derivation against a low-bit diffusion bug. Per Phase 230 D-06, `230-01-DELTA-MAP.md` is READ-only; this addendum extends the v29.0 audit surface record without amending it.

`230-01-DELTA-MAP.md` + this file together form the authoritative scope for downstream phases 233-236. Phase 231 completed before these commits landed; Phase 232 plans were written before they landed but do not overlap.

## Commits added to v29.0 scope

### `314443af` — fix(traits): keccak-seed per group to decorrelate categories across players

**File:** `contracts/modules/DegenerusGameMintModule.sol`
**Function modified:** `_raritySymbolBatch` (lines 559-571 at HEAD)
**Delta:** LCG seed derivation replaced.

```
- uint32 groupIdx = i >> 4; // Group index (per 16 symbols)
- uint256 seed;
- unchecked {
-     seed = (baseKey + groupIdx) ^ entropyWord;
- }
- uint64 s = uint64(seed) | 1; // Ensure odd for full LCG period
+ uint32 groupIdx = i >> 4;
+ uint256 seed = uint256(
+     keccak256(abi.encode(baseKey, entropyWord, groupIdx))
+ );
+ uint64 s = uint64(seed) | 1;
```

**Bug class:** Player address stored in `baseKey` bits 32-191; the low 32 bits of `seed` (consumed by `uint64(seed) | 1` → LCG → `traitFromWord(uint64)` → category bucket) inherited zero player-address entropy from the `+ groupIdx` and `^ entropyWord` ops. Multiple players sharing an `entropyWord` (e.g. lootbox VRF index reuse) received identical category sequences. Simulation: ~60% of trait IDs received zero tickets per level under typical sharing (81 opens/index).

**Audit verdict:** SAFE (self-audit, fresh read). Keccak256 of `abi.encode(uint256, uint256, uint32)` diffuses all inputs across all 256 output bits; `uint64(seed)` now draws from a cryptographically uniform low word. Downstream LCG iteration (`s = s * (TICKET_LCG_MULT + offset) + offset`) preserves low-bit independence since the seed is already uniform. No new attack surface, no CEI/reentrancy implications (function is internal pure from the call-path perspective).

**Finding candidate:** N (fix, not a finding).

### `c2e5e0a9` — fix(rng): replace XOR+xorshift entropy mixing with keccak

**Files modified:**

| File | Sites |
|------|-------|
| `contracts/libraries/EntropyLib.sol` | NEW `hash2(uint256, uint256) → uint256` (memory-safe asm scratch slots 0x00/0x20) |
| `contracts/modules/DegenerusGameMintModule.sol` | `_rollRemainder` (line 647) |
| `contracts/modules/DegenerusGameJackpotModule.sol` | 16 sites (lines 277, 443, 508, 522, 544, 594, 596, 607-609, 874, 937, 1134, 1238, 1345, 1681-1683, 1741, 1798-1800, 1808) |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | `_calcAutoRebuy` (line 68-70) |

**Bug class (identical to `314443af`):** 17 sites XOR-mixed structured high-bit inputs (level, trait index, player address, queue index, domain-separator tags) into VRF entropy, then passed through `EntropyLib.entropyStep` — a single-iteration uint256 xorshift that diffuses bits only ~40 positions outward. Upper-bit inputs were invisible to low-bit consumers (`% N`, `& mask`).

**Per-file verdict table:**

| File:Line | Function | Attack Vector | Verdict | Evidence | SHA |
|---|---|---|---|---|---|
| `contracts/libraries/EntropyLib.sol:26-37` | `hash2(uint256, uint256)` | memory-safety correctness (asm scratch slots) | SAFE | Uses reserved scratch 0x00-0x3F only; `memory-safe` annotation valid per Yul spec; output identical to `uint256(keccak256(abi.encode(a, b)))` for the same inputs | c2e5e0a9 |
| `contracts/modules/DegenerusGameMintModule.sol:647` | `_rollRemainder` | player-address entropy reaches `% TICKET_SCALE` | SAFE | `hash2(entropy, rollSalt)` diffuses all 256 bits of both inputs; low 7 bits now carry full player-address entropy | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:277` | `_runDailyEthOnlyAndBonus` | level domain separation for `entropy & 3` + `entropy >> 24 & 3` consumers | SAFE | `hash2(rngWord, targetLvl)` | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:443,544,594,874,1134` | `payDailyJackpot` / `_executeJackpot` / `payDailyJackpotCoinAndTickets` / `_distributePurchasePhaseTickets` / `_resumeDailyEth` | same as 277 (5 sites, identical `hash2(randWord, lvl)` invocation) | SAFE | Each site produces a distinct `entropyDaily` / `entropyPurchase` / etc. but all with full diffusion of `lvl` into low bits | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:596` | `payDailyJackpotCoinAndTickets` | carryover source-level decorrelation | SAFE | `hash2(randWord, sourceLevel)` now produces a low-bit output that differs from `entropyDaily` at line 594 — fixing the cross-carryover correlation concern flagged in 231-02 Downstream Hand-offs | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:508,522,1681` | `payDailyJackpot` (coin branches) / `_awardDailyCoinJackpotInRange` | COIN_JACKPOT_TAG domain separation + level decorrelation | SAFE | `keccak256(abi.encode(randWord, lvl, COIN_JACKPOT_TAG))` — full diffusion of all 3 inputs | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:607-609` | `payDailyJackpotCoinAndTickets` (coin near-budget) | same as 508/522 | SAFE | Identical 3-input hash shape | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:937,1238,1345,1741` | `_distributeTicketsToBuckets` / `_processDailyEth` bucket loops / `_awardDailyCoinToTraitWinners` | per-bucket trait-index decorrelation | SAFE | `keccak256(abi.encode(entropy, traitIdx, X))` where X is ticketUnits / share / traitShare / coinBudget — full diffusion per iteration; no collision surface since entropy advances monotonically inside the loop | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:1798-1800` | `_awardFarFutureCoinJackpot` (initial seed) | FAR_FUTURE_COIN_TAG domain + level decorrelation | SAFE | `keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_COIN_TAG))` | c2e5e0a9 |
| `contracts/modules/DegenerusGameJackpotModule.sol:1808` | `_awardFarFutureCoinJackpot` (sample loop) | per-sample iteration decorrelation | SAFE | `hash2(entropy, s)` inside the 10-iteration loop — each sample now draws from a uniformly-random seed; previous `entropyStep(entropy ^ s)` was marginal but adequate, the keccak formulation is strictly stronger | c2e5e0a9 |
| `contracts/modules/DegenerusGamePayoutUtils.sol:68-70` | `_calcAutoRebuy` | auto-rebuy level-offset roll | SAFE | `keccak256(abi.encode(entropy, beneficiary, weiAmount))` — was already marginally safe (beneficiary in low 160 bits reached the `& 3` consumer via xorshift diffusion), now strictly safe via full keccak diffusion | c2e5e0a9 |

**Cryptographic collision analysis:** The mix of `hash2` (asm scratch-slot) and `keccak256(abi.encode(...))` formulations produces outputs over different input byte layouts. Collision analysis:

- `hash2(a, b)` hashes exactly 64 bytes: `[32-byte a][32-byte b]`.
- `keccak256(abi.encode(a, b, c))` hashes 96 bytes: `[32-byte a][32-byte b][32-byte c]`.
- Different lengths → different preimages → keccak collision-resistance guarantees no accidental cross-formulation collisions.

**Cryptographic domain-separation analysis:** Each 3-input site uses a UNIQUE compile-time TAG constant (`COIN_JACKPOT_TAG = keccak256("coin-jackpot")`, `FAR_FUTURE_COIN_TAG = keccak256("far-future-coin")`). Different TAGs → disjoint preimages → disjoint outputs. 2-input `hash2` sites pass no TAG — they rely on distinct `(randWord, lvl)` or `(entropy, iterator)` pairs to separate. No cross-site domain-collision surface.

**Gas impact (measured):**
- Per-call delta asm-`hash2` vs original xorshift: **+18 gas** (forge microbench, 1000 iters).
- Per-call delta `keccak256(abi.encode(a,b,c))` vs original xorshift: **+201 gas** (isolated) but called ≤1 per VRF fulfillment.
- Worst-case Sybil 550× `_rollRemainder` per ticket batch: +9,900 gas (+0.14% of 6.95M batch budget).
- Realistic jackpot path deltas: ±2-7% depending on random-path divergence, NOT the keccak cost itself.

**Finding candidate:** N (fix, not a finding).

## Downstream phase impact

| Phase | Status | Overlap | Action |
|---|---|---|---|
| **231 EBD-01/02/03** | COMPLETE | None (earlybird functions `_finalizeEarlybird`, `_awardEarlybirdDgnrs`, `_runEarlyBirdLootboxJackpot`, `_rollWinningTraits` are NOT touched by either new commit) | No re-audit. 231 verdicts remain valid. |
| **232 DCM-01/02/03** | PLANNED | None (decimator functions untouched) | Execute 232 plans as-written. |
| **233 JKP-01/02/03** | CONTEXT DONE | **HIGH** — every JKP requirement targets functions touched by `c2e5e0a9` | 233 CONTEXT.md amended with D-10 referencing this addendum. Plans must include verdict rows for the post-`c2e5e0a9` state of every in-scope function. |
| **234 QST/BOON/MISC** | CONTEXT DONE | Low — `_calcAutoRebuy` in PayoutUtils may enter scope via whale-bundle auto-rebuy path | 234 CONTEXT.md amended with a brief overlap note. |
| **235 CONS/RNG/TRNX** | NOT PLANNED | **HIGH** for RNG-01/02 — every new `hash2` / `abi.encode` keccak site is a new RNG consumer that needs commitment-window back-trace | 235 planning must include this addendum in scope source. |
| **236 REG/FIND** | NOT PLANNED | **HIGH** — REG-01 regression sweep must confirm `_raritySymbolBatch`/`_rollRemainder` still produce valid trait distributions; FIND-01 consolidation notes both fixes as finding-candidate-free | 236 planning must include this addendum. |

## Scope-guard rule

`230-01-DELTA-MAP.md` remains READ-only per Phase 230 D-06. This addendum extends the scope record WITHOUT amending the original catalog. Downstream phases read BOTH files. Any future post-addendum contract change that introduces a new audit surface gets its own `230-NN-DELTA-ADDENDUM.md` file — no in-place edits to `230-01` or `230-02`.

## Files reference

- `230-01-DELTA-MAP.md` — original 10-commit delta catalog
- `230-02-DELTA-ADDENDUM.md` — THIS FILE, extends with 2 post-Phase-230 commits
- `230-01-SUMMARY.md` — original Phase 230 summary; not amended

---

*Phase: 230-delta-extraction-scope-map*
*Addendum added: 2026-04-17 (post-Phase-231 execution, pre-Phase-232 execution)*
