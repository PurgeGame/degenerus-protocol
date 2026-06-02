---
phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
plan: 05
subsystem: test-fuzz (QST-04 quest-core non-perturbation proof)
tags: [qst-04, d-04, quest-core, afking-active, streak-neutral, byte-identity, o1-single-credit, non-perturbation]
requires:
  - "356-02 (the v56-migrated V55SetMutationOpenE funded-sub fixture + the canonical v56 Sub offsets)"
  - "the v56 shared-DegenerusQuests core frozen in contracts/ (subject 453f8073 IMPL diff committed/frozen)"
provides:
  - "V56QuestNonPerturb — the QST-04 (D-04) FULL empirical quest-core non-perturbation proof"
  - "slot-1 streak-neutral-during-afking + accessible + NON-afking-advance (the afkingActive gate)"
  - "cross-caller byte-identity (afking subs present vs absent) on awardQuestStreakBonus + a slot completion"
  - "the O1 lootbox-quest single-credit regression (the v56 fix holds, double-credit not re-introduced)"
affects:
  - "356-07 (the empirical 453f8073-baseline NON-WIDENING union — receives this NEW green suite, 7/7)"
  - "357 AUDIT-01 (the quest-core non-perturbation is empirically proven here, not deferred)"
tech-stack:
  added: []
  patterns:
    - "Drive the access-gated DegenerusQuests core directly: vm.prank(GAME) for onlyGame (rollDailyQuest / beginAfking / awardQuestStreakBonus / finalizeAfking), vm.prank(COIN) for onlyCoin handlers (handleMint / handleFlip / handleDecimator / handleAffiliate / handlePurchase)"
    - "PlayerQuestState single-slot byte read: vm.load(QUESTS, keccak256(abi.encode(player, 2))) — questPlayerState root = slot 2, struct packs into one 256-bit word (lastActiveDay u24 byte-3, streak u16 byte-9, afkingActive bool byte-13)"
    - "Two-world byte-identity via vm.snapshotState/vm.revertToState (NOT a linear re-run): identical target path, afking siblings present vs absent, assert the full packed word equal"
key-files:
  created:
    - test/fuzz/V56QuestNonPerturb.t.sol
  modified: []
decisions:
  - "Slot-1 terminology mapped to the shipped code: the afkingActive gate in _questComplete (:1751 `if (!afking && (mask & CREDITED) == 0)`) suppresses the streak bump on the FIRST completion of EITHER slot while afking, and zeroes the slot-0 immediate reward (:1763); slot-1 (the player's own random quest) still pays its full QUEST_RANDOM_REWARD (=200 BURNIE). Proved BOTH: slot-0 streak-neutral + slot-1 accessible+streak-neutral, plus the NON-afking +1 control."
  - "Drove the quest core directly through its GAME/COIN access gates rather than through the full game-advance machinery — isolates exactly the afkingActive gate + the per-player slot keying, deterministic and fixture-light. rollDailyQuest(day, entropy) sets a known currentDay; day-4 entropy deterministically rolls slot-1 = LOOTBOX (the O1 region), confirmed by a throwaway probe."
  - "O1 single-credit isolated the LOOTBOX leg: completed slot-0 in a separate handleMint, then a lootbox-only handlePurchase(ethMintSpendWei=0). The v56 fix RETURNS the lootbox reward to the caller (single QUEST_RANDOM_REWARD) and does NOT internally creditFlip it (coinflipAmount stays 0) — the double-credit is provably not re-introduced. (An earlier all-in-one handlePurchase returned 300 = 100 slot-0 + 200 lootbox; isolating the leg makes the single-credit assertion exact — a Rule 1 test-logic fix, no contract touched.)"
  - "Byte-identity is asserted on the FULL packed PlayerQuestState word (one slot), not field-by-field — questPlayerState[target] is keyed only on target, so a sibling's beginAfking/finalizeAfking write cannot perturb it; the whole-word equality is the strongest cross-caller non-perturbation statement."
metrics:
  duration: ~40m
  completed: 2026-06-02
  tasks: 2
  files: 1
---

# Phase 356 Plan 05: QST-04 (D-04) Quest-Core Non-Perturbation — slot-1 streak-neutral + cross-caller byte-identity + O1 single-credit Summary

Authored `test/fuzz/V56QuestNonPerturb.t.sol` — the QST-04 (D-04) FULL empirical quest-core non-perturbation proof, a NEW green suite passing against v56 HEAD (7/7). It proves (a) during afking a quest completion is STREAK-NEUTRAL yet the player's own random/manual slot stays FULLY ACCESSIBLE (pays its 200-BURNIE reward), while a NON-afking player's identical completion advances the streak by 1 — the gate is exactly `afkingActive`, keeping the C3-a non-funded streak dodge closed; and (b) `awardQuestStreakBonus` + the manual quest-reward callers produce a byte-identical target `PlayerQuestState` with afking subs present vs absent, with the O1 lootbox-quest single-credit holding across both worlds.

## What Shipped

One new Foundry suite, `contract V56QuestNonPerturb is DeployProtocol`, 374 lines, 7 tests, all green against v56 HEAD. Zero `contracts/*.sol` mutation; `ContractAddresses.sol` restored after every patch round-trip.

Confirmed the DegenerusQuests storage layout via `forge inspect DegenerusQuests storageLayout`: `questPlayerState` mapping root = **slot 2**; the `PlayerQuestState` struct packs into a single 256-bit word — `lastActiveDay` u24 byte-3, `streak` u16 byte-9, `afkingActive` bool byte-13. The suite reads the whole word via `vm.load(QUESTS, keccak256(abi.encode(player, 2)))` and cross-checks `streak` against the public `playerQuestStates` view.

### Task 1 — slot-1 streak-neutral during afking + accessible + NON-afking advance — commit `b25c7e33`
Four tests exercising the `afkingActive` gate in `DegenerusQuests._questComplete` (`:1751` `if (!afking && (mask & QUEST_STATE_STREAK_CREDITED) == 0)`):
- `testSlot1NonAfkingAdvancesStreakNormally` — the control: a NON-afking player's slot-0 (own funded MINT_ETH) completion advances `state.streak` by 1 (5 -> 6).
- `testStreakNeutralDuringAfkingSlot0` — during afking the slot-0 completion succeeds (accessible) yet `state.streak` is UNCHANGED (streak-neutral).
- `testSlot1AccessibleAndStreakNeutralDuringAfking` — the player's own random/manual slot (slot 1) completes during afking AND pays its full `QUEST_RANDOM_REWARD` (200 BURNIE); the streak still does not advance.
- `testStreakNeutralIsGatedByAfkingActiveOnly` — the decisive control pair: the SAME slot-0 completion is neutral for an afking player (9 -> 9) but advances for a non-afking player (9 -> 10) in one test, proving the gate is exactly `afkingActive`.

### Task 2 — cross-caller byte-identity (afking present vs absent) + O1 single-credit — commit `ad3fbbcd`
Three tests using `vm.snapshotState`/`vm.revertToState` two-world comparison:
- `testByteIdentAwardStreakBonusWithAfkingPresentVsAbsent` — the target's `awardQuestStreakBonus` path yields a byte-identical `PlayerQuestState` word whether or not OTHER players hold afking subs (one sibling mid-`finalizeAfking`); non-vacuity: the target streak actually moved (4+3=7).
- `testByteIdentCrossCallerCompletionWithAfkingPresentVsAbsent` — a streak bonus + slot-0 + slot-1 completion path is byte-identical across the two worlds; non-vacuity: streak 6 -> 7 and `lastActiveDay` bumped.
- `testO1LootboxSingleCreditAcrossTwoWorlds` — day-4 slot-1 rolls LOOTBOX (the O1 region); the lootbox reward is RETURNED once (single 200 BURNIE) and is NOT internally creditFlipped (`coinflipAmount` stays 0), identically with afking siblings present or absent — the v56 single-credit fix is not re-introduced.

## Verification

- `forge build` EXIT 0 (`Compiler run successful`).
- `forge test --match-contract V56QuestNonPerturb` — **7 passed, 0 failed, 0 skipped**.
- Per-task match runs green: Task 1 (`Slot1|StreakNeutral|Accessible|NonAfking`) 4/4; Task 2 (`ByteIdent|...|O1|SingleCredit`) 3/3.
- `git diff --quiet HEAD -- contracts/` exits 0 throughout — ZERO `contracts/*.sol` mutation; `ContractAddresses.sol` restored after every patch round-trip.
- Storage offsets confirmed empirically via `forge inspect DegenerusQuests storageLayout` against HEAD (not assumed from training).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test-logic bug] O1 single-credit: isolate the LOOTBOX leg**
- **Found during:** Task 2
- **Issue:** The first O1 draft drove an all-in-one `handlePurchase(ethMintSpendWei=1 ether, lootBoxAmount=1 ether)`, which completed BOTH slot-0 (MINT_ETH, returns 100 BURNIE) and slot-1 (LOOTBOX, returns 200 BURNIE) in one call, so the returned reward was 300 — failing the exact single-200 assertion. That is CORRECT contract behavior (both slots completed), not a contract bug.
- **Fix:** Complete slot-0 first in a separate `handleMint`, then drive a lootbox-only `handlePurchase(ethMintSpendWei=0, lootBoxAmount=1 ether)` so the returned reward is purely the single lootbox 200 BURNIE — making the single-credit assertion exact (returned once + `coinflipAmount` unchanged = no internal double-credit).
- **Files modified:** `test/fuzz/V56QuestNonPerturb.t.sol` (`_completeLootboxSlot1` helper)
- **Commit:** `ad3fbbcd`

Otherwise the plan executed as written.

## Threat Flags

None. The QST-04 surface (the shared DegenerusQuests core under the new afking entrypoints) was reachable directly via the GAME/COIN access gates; no fixture dispatch-stub gap was hit (unlike the `drainAffiliateBase` gap that 356-03/04 flagged). The two D-04 properties are proven empirically at the quest-state level here — no observation deferred to 357 for this plan.

## Known Stubs

None. Every test asserts a live shipped property against v56 HEAD; no hardcoded/placeholder data flows to any assertion. Non-vacuity is anchored in each two-world test (the target path provably moves state) and in each streak test (the NON-afking +1 control).

## Self-Check: PASSED

- test/fuzz/V56QuestNonPerturb.t.sol — FOUND (374 lines, `contract V56QuestNonPerturb`, >150 min_lines).
- Commit `b25c7e33` (Task 1) — present in git log.
- Commit `ad3fbbcd` (Task 2) — present in git log.
- `git diff --quiet HEAD -- contracts/` exits 0 — ZERO contract mutation.
- `forge test --match-contract V56QuestNonPerturb` — 7/7 PASS against v56 HEAD.
