---
phase: 436-impl-batched-contract-diff-points-streak-pack-contract-commi
plan: 01
type: execute
status: complete
commit: c4b09267
subject_tree: 2eeed00592bbb0bd0789f0e36530e9330f3e2279
requirements: [POINTS-01, POINTS-02, STREAK-01, STREAK-02, PACK-01]
---

# 436-01 SUMMARY — Batched POINTS + STREAK + PACK contract diff

**Outcome:** the v69 activity-score change landed as ONE atomic, USER-approved `contracts/*.sol`
commit (`c4b09267`) across six files. This is the sole `.sol` change of the v69 milestone and its
only approval gate. The new byte-frozen subject is `contracts/` tree `2eeed005` (baseline was the
v68 closure subject, `contracts/` tree `e9a5fc24`). Proving (437 TST) and re-auditing (438 REAUDIT)
run against this subject.

## Per-track / per-file change map

### POINTS (bps → whole points)
- **`contracts/modules/DegenerusGameMintStreakUtils.sol`** — `_playerActivityScoreAt` collapsed to
  the point domain: deity base `50*100`/`+25*100` → `50`/`+25`; mint-streak/mint-count/affiliate
  `*100` dropped; whale `+1000`/`+4000` → `+10`/`+40`; curse penalty `curse*100` → `- curse`. The
  sole sub-point leg, quest streak `questStreak*50` → **`questStreak / 2`** (floor, D-02). Cap clamp →
  `ACTIVITY_SCORE_HARD_CAP_POINTS` (= **65_534**, D-436-09). Return var `scoreBps`→`scorePoints` (3
  signatures). `PASS_STREAK_FLOOR_POINTS`/`PASS_MINT_COUNT_FLOOR_POINTS` already point-domain — unchanged.
- **`contracts/storage/DegenerusGameStorage.sol`** (TABLE-A renames): `DEITY_PASS_ACTIVITY_BONUS_POINTS=80`,
  `ACTIVITY_SCORE_HARD_CAP_POINTS=65_534`, `LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS=60`,
  `LOOTBOX_EV_ACTIVITY_MAX_POINTS=400`. `_lootboxEvMultiplierFromScore` shape unchanged (scale-invariant).
- **`contracts/modules/DegenerusGameDegeneretteModule.sol`**: `ACTIVITY_SCORE_MID/HIGH/MAX_POINTS = 75/255/305`;
  `_roiBpsFromScore` (quadratic + linear) and `_wwxrpHighValueRoi` are scale-invariant — shape unchanged.
- **`contracts/modules/DegenerusGameDecimatorModule.sol`**: `TERMINAL_DEC_ACTIVITY_CAP_POINTS=235`; the
  burn multiplier re-scales to **`BPS_DENOMINATOR + (bonusPoints*100)/3`** (the one non-scale-invariant
  migration). `_terminalDecBucket` scale-invariant.
  - **Source-truth correction (verified):** the design-lock's "keep-alive mirror" is the CLAMP + bucket
    mirror, NOT a second `/3` multiplier. `recordTerminalDecKeepAlive`'s `factorBps` comes from
    `_terminalDecBoostFactorBps(effectiveStreak)` — a streak-keyed (`streak*3000`) weight boost in bps,
    correctly TABLE-B and untouched. The `(points*100)/3` re-scale therefore appears at exactly the one
    site where the `/3`-on-activity-score multiplier lives.

### STREAK (single exact integer path)
- **`contracts/storage/DegenerusGameStorage.sol`**: `subStreakLatch` uint8→**uint16**; `SUB_STREAK_MASK
  0xff→0xffff`; `_streakBaseOf` returns uint16; `_setStreakBase` clamp **re-pinned `255`→`type(uint16).max`**
  (KEPT — guards the live `recordAfkingSecondary` +1 bump from wrapping 65536→0 at the ceiling).
- **`contracts/modules/GameAfkingModule.sol`**: latch follow-through rides uint16 (no behaviour change);
  +1-bump saturation comment → 65535.
- **`contracts/DegenerusQuests.sol`**: **deleted** the `finalizeAfking` floor-hack (`uint16 preRun` restore
  + comment); the widened uint16 latch now carries the pre-run snapshot exactly. Decay logic and the final
  `type(uint16).max` safety clamp retained; `PlayerQuestState.streak` (uint16) + `beginAfking` unchanged.

### PACK (pendingFlip uint24 + net-zero accumulator repack)
- **`contracts/storage/DegenerusGameStorage.sol`**: `Sub.pendingFlip` uint32→**uint24**; slot/section/field
  comments reconciled to the new widths.
- **`contracts/modules/GameAfkingModule.sol`**: both accrue sites (ticket buyer-bonus + slot-0 quest-reward)
  re-pinned `100_000_000`→**`type(uint24).max`** with `uint24(newOwed)` casts (lossless — clamp precedes cast).
  `_settlePendingFlip` widen-back holds. **`affiliateBase` 100M clamp (`:921`) untouched** (D-436-08).

## Empirical pre-approval gate (independently re-run by orchestrator)
- **forge build:** exit 0, clean (only pre-existing `unsafe-typecast` advisory lints).
- **EIP-170 (PACK-01):** `DegenerusGame` deployed bytecode = **20,388 bytes** → **4,188 B headroom** under
  24,576 (net-neutral).
- **Sub slot sanity (`forge inspect ... storageLayout`):** `Sub` = **one 32-byte slot, 0 free**; accumulator
  `affiliateBase(32, off 23) + pendingFlip(24, off 27) + subStreakLatch(16, off 30) = 72` bits, ending exactly
  at byte 32. Net-zero repack (was 32+32+8=72 too); no new slot, no collision. The intra-slot offset move is
  the EXPECTED new golden — recaptured in 438 REAUDIT-01, not a drift.
- **Baseline-parity smoke (touched-surface `--match-contract`):** 29 structural pass / 1 expected-golden-red /
  1 skip. The single red — `KeeperLeversAndPacking::testGas04PackingAndNoNewHotPathStorageSourcePresence` —
  greps the source for the literal **pre-PACK** declarations `uint32 pendingFlip;` / `uint8 subStreakLatch;`;
  the PACK width change makes the grep miss → `_structFieldBytes` returns `type(uint256).max` → the byte-sum
  overflows. This is the v56-era storage-layout golden, which the design-lock defers (golden recapture → 438
  REAUDIT-01; test update → 437 TST). NOT a structural regression — the real layout is proven correct above.

## D-436-09 reconciliation confirmation
The activity-score hard cap is `ACTIVITY_SCORE_HARD_CAP_POINTS = 65_534` (rename-only, value unchanged — NOT
floored to 655). No bare `655` appears in any of the six files. The uint16-sentinel overflow rationale comment
becomes true verbatim (`65534 + 1 = 65535` fits uint16, one below max, 0 reserved as the sDGNRS unset
sentinel) and was kept with only the `bps`→`points` unit token reworded. `Sub.score` stays uint16.

## DO-NOT-TOUCH confirmation
`affiliateBase` (uint32, 100M clamp) · `Sub.score` (uint16) · `lootboxRngPendingFlip` (uint40) · all TABLE-B
output bps (`LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS=9_000/10_000/14_500`, `ROI_*_BPS`, `WWXRP_*_BPS`, quadratic coeffs
1000/500, `BPS_DENOMINATOR=10_000`) · bucket counts (range=10) — all verified unchanged.

## Single commit
- **`c4b09267`** — `feat(436): activity score in whole points + single integer streak path + pendingFlip
  uint24 repack`. Exactly six `.sol` files; no intermediate `contracts/*.sol` commit in any earlier task.
  Committed via the pre-commit hook move-aside + `CONTRACTS_COMMIT_APPROVED=1` (PreToolUse layer), after
  explicit USER hand-review approval at the Task 6 gate. UNPUSHED (push is a separate USER action).

## Handoff
This is the new v69 byte-frozen subject (`contracts/` tree `2eeed005` @ `c4b09267`). **437 TST** writes the
behavioural proof (incl. updating the `testGas04` layout golden to the new uint24/uint16 widths and any
value-asserting score/streak tests to the point domain). **438 REAUDIT** re-runs the RNG-freeze proof, the
storage-layout golden recapture (REAUDIT-01), the point-domain consumer-equivalence + sDGNRS snapshot
re-confirm + off-chain indexer re-vendor (REAUDIT-02), and the mutation campaign — v68 methodology carries
forward.
