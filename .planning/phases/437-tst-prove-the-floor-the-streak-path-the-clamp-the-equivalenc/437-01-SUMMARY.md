---
phase: 437-tst-prove-the-floor-the-streak-path-the-clamp-the-equivalenc
plan: 01
type: execute
status: complete
requirements: [TST-01]
subject_tree: 2eeed00592bbb0bd0789f0e36530e9330f3e2279
subject_commit: c4b09267
provides: "Floor-rule + exact-integer-streak-path proofs against the shipped point-domain activity score"
requires: "v69 byte-frozen subject (contracts/ tree 2eeed005 @ c4b09267)"
affects: []
key-files:
  created:
    - test/fuzz/ActivityScorePointFloor.t.sol
  modified: []
decisions:
  - "Quest leg drives the score via a direct questPlayerState write (non-afker, day anchors 0) — a deterministic, decay-inert read of state.streak."
  - "The afking quest leg is read from the SCORE (score - 155 deity baseline), not the QUEST-side getter: effectiveBaseStreakAndAfking returns the manual snapshot for an afker, while the score consumes the GAME-side _liveAfkingStreak compute-on-read."
  - "XOR is proven with live and manual values that floor to DIFFERENT points (live 9 -> 4, manual 4 -> 2) so a summed-both or stuck-on-one implementation fails."
metrics:
  tasks_completed: 2
  files_changed: 1
  test_functions: 4
  commits: 2
---

# Phase 437 Plan 01: Prove the Floor, the Streak Path & the Exact-Integer Equivalence Summary

**One-liner:** A new forge proof (`ActivityScorePointFloor.t.sol`, 4 tests) pins the whole-point activity score's
sole sub-point leg at `floor(questStreak/2)`, shows it is the exact integer image of the retired `questStreak*50`
bps leg, and proves the manual streak and the live afking-run streak base feed the score through one exact integer
path with afking-XOR-manual exclusivity — all against the v69 byte-frozen subject (`c4b09267`), zero contract change.

## What was proven (TST-01)

### Task 1 — the floor rule + the bps-equivalence identity (commit `bac8bdb7`)
- `test_QuestStreakFloorRule_BpsEquivalence` — across the grid `{0,1,2,3,4,5,6,7,8,9,10,49,50,51,100,255,1000,32767}`
  asserts the D-02 identity `q/2 == (q*50)/100` (uint256 integer math), then pins the even/odd boundaries
  (`4->2`, `5->2`, `6->3`, `7->3`). The odd assertions name the rejected alternatives in-comment: a round-half-up
  policy (`5->3`, `7->4`) or a 0.5-pt-granular representation would diverge — the test fails-without the floor.
- `test_QuestStreakLegIsoEndToEnd` — drives `game.playerActivityScore` on a fresh fixture where the quest leg is
  the sole contributor (at deploy `level == 0`, so `_mintCountBonusPoints` and the affiliate cached leg both read 0;
  no deity pass / whale bundle / curse; `_mintStreakEffectiveFromPacked` returns 0). An odd manual streak of 7 yields
  a clean whole-point score of exactly **3** (`floor(7/2)`, not 3.5, not the round-half-up 4). The even/odd difference
  pairs (`6 vs 7 -> +0`, `8 vs 9 -> +0`, `8 vs 10 -> +1`) independently witness the dropped half-point.

### Task 2 — the single exact integer streak path + afking-XOR-manual exclusivity (commit `4ed37f91`)
- `test_LiveAfkingStreakFeedsScore_XOR` — a deity-passed afker (score baseline 155 = 50+25+80, zero affiliate) with a
  dormant manual streak of 4 delivers funded days until the live compute-on-read streak (`base + covered - start`)
  reaches an odd value of 9. Read while LIVE, the score's quest leg is `score - 155 == 4 == floor(9/2)` — the LIVE
  source, **not** the manual fallback (`floor(4/2)=2`). A missed-funded-day decay gap then drops the run, and the
  re-read score's quest leg is `score - 155 == 2 == floor(4/2)` — the manual source. The two values floor to
  different points, so a summed-both-sources (`4+2=6`) or stuck-on-one implementation fails: exactly one source feeds
  the score at a time.
- `test_ExactIntegerCombine_NoFractionalIntermediate` — an afker with a zero manual snapshot drives the live total to
  an odd value, and the whole-point score's quest leg is exactly `floor(total/2)` with the trailing half-point dropped
  (`2*floor(total/2) + 1 == total`). A half-point intermediate anywhere in the base + funded-days combine (the retired
  `*50` bps path could carry one) would have surfaced as `score - 155 != floor(total/2)`.

## Key mechanical findings (drive correctness)

- **The score reads the LIVE afking value, the QUEST getter reads the manual snapshot.** `effectiveBaseStreakAndAfking`
  returns the dormant manual streak + `afking=true` for an afker; the score consumes the GAME-side `_effectiveQuestStreak`
  → `_liveAfkingStreak` compute-on-read. The proof therefore reads the afking quest leg from the score (`score - 155`),
  not from the getter. Confirmed empirically: a live odd value of 9 produced score 159 (`155 + 4`); the same player after
  decay produced 157 (`155 + 2`).
- **The afking base is the manual streak snapshot taken at `beginAfking` (subscribe), not 0** — it only re-bases to 0 when
  the run lapses (`covered + 1 < processDay`). The XOR test sets the manual streak before subscribing so the snapshot and
  the live value are both controlled.
- **The deity baseline is exactly 155** (`DEITY_PASS_ACTIVITY_BONUS_POINTS=80` + deity base `50+25`) with zero affiliate
  when the live streak matches the score exactly — verified against a deity-only no-streak player.

## Authoritative layout used (re-derived from the v69 storageLayout, not the V56 pre-PACK offsets)

- **PlayerQuestState** (DegenerusQuests slot 1 mapping, one packed slot): `lastSyncDay` u24 off6, `streak` u16 off9,
  `baseStreak` u16 off11, `afkingActive` bool off13. The manual drive writes `streak` and a non-zero `lastSyncDay`
  with the day anchors 0, so `_effectiveBaseStreak` skips its decay branch and returns `state.streak` verbatim.
- **Sub** (DegenerusGame slot 54 mapping, one packed slot, post-PACK accumulator): `afkCoveredThroughDay` u24 off17,
  `afkingStartDay` u24 off20, `affiliateBase` u32 off23, **`pendingFlip` u24 off27**, **`subStreakLatch` u16 off30**.
  The latch widened 8->16 and pendingFlip narrowed 32->24 in v69; the V56 file's `OFF_PENDINGFLIP=27/width-32` /
  `OFF_STREAKLATCH=31/width-8` are the OLD layout and were NOT copied.

## Constants confirmation
- Asserts against the SHIPPED point-domain behaviour: `floor(questStreak/2)`, deity baseline 155, point-domain legs.
- **Zero references to `655`.** The hard cap is `ACTIVITY_SCORE_HARD_CAP_POINTS = 65_534` (gameplay-inert here — every
  consumer clamps <= 400), so the cap value is not exercised by these proofs and no bare cap literal is asserted.

## Verification
- `forge test --match-contract ActivityScorePointFloorTest -vv` → **4 passed, 0 failed, 0 skipped**.
- `git status` shows only the new test file (+ a pre-existing untracked `PLAYER-PURCHASE-REWARDS.html`, unrelated and
  untouched). **No `contracts/*.sol`, `STATE.md`, or `ROADMAP.md` modification.**

## Deviations from Plan
None — plan executed as written. The plan offered a fallback for Task 1's end-to-end (score-difference pairs if absolute
isolation was unreachable); absolute isolation WAS reachable (fresh player at level 0 scores purely from the quest leg),
so the test asserts both the absolute `streak 7 -> score 3` AND the difference pairs for redundancy.

## TDD Gate Compliance
This is a test-writing plan against an already-frozen, already-correct subject (`c4b09267`). The tests are proofs that
assert the SHIPPED behaviour, so they pass on first run by construction — the fails-without structure (pinned floored
values at odd boundaries; live/manual values that floor to different points) is what guarantees a regression in the
contract would be caught. No `contracts/*.sol` change was made or needed (test-only phase). Both tasks committed
individually as `test(...)` commits.

## Self-Check: PASSED
- `test/fuzz/ActivityScorePointFloor.t.sol` — FOUND (351 lines, 4 test functions).
- Commit `bac8bdb7` (Task 1) — FOUND.
- Commit `4ed37f91` (Task 2) — FOUND.
