// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";

/// @title V56QuestNonPerturb -- QST-04 (D-04): the v56 quest-core non-perturbation proof.
///
/// @notice Two properties of the shared DegenerusQuests core, now that the afking redesign added
///         `beginAfking` + the `finalizeAfking` write entrypoint alongside the pre-existing
///         manual/bingo/degenerette/boon callers:
///
///   (a) SLOT-1 STREAK-NEUTRAL + ACCESSIBLE during afking. While `afkingActive` is set (begun via
///       `beginAfking`), a quest completion of EITHER slot is streak-neutral — the compute-on-read
///       afking streak (off the Game-side Sub slot) owns the streak, so the manual `state.streak`
///       must NOT advance (`DegenerusQuests._questComplete`: `if (!afking && (mask & CREDITED) == 0)`,
///       :1751). The player's own random/manual slot stays FULLY ACCESSIBLE (the completion succeeds
///       and pays its `QUEST_RANDOM_REWARD`; only the streak bump is suppressed). For a NON-afking
///       player the same completion advances `state.streak` by 1 — the gate is `afkingActive`, not a
///       global suppression. This keeps the C3-a non-funded streak dodge closed (a cheap slot-1
///       completion can no longer hold a lapsed afking streak alive).
///
///   (b) CROSS-CALLER BYTE-IDENTITY. `awardQuestStreakBonus` + the manual quest-reward callers produce
///       a byte-identical PlayerQuestState for a TARGET player whether or not OTHER players hold afking
///       subs (have `afkingActive` set). The per-player `questPlayerState[target]` slot is keyed only
///       on `target`, so a sibling's `beginAfking`/`finalizeAfking` write cannot perturb it; the test
///       asserts the full packed PlayerQuestState word is identical across the two worlds. The O1
///       single-credit invariant rides along: a completed quest credits its BURNIE reward exactly once
///       across the two worlds.
///
/// @dev Drives the DegenerusQuests core directly through its access-gated entrypoints — pranking the
///      GAME address for the `onlyGame` surface (`rollDailyQuest`/`beginAfking`/`awardQuestStreakBonus`/
///      `finalizeAfking`) and the COIN address for the `onlyCoin` progress handlers
///      (`handleMint`/`handleFlip`/...). State is read through the `playerQuestStates` view (streak) and
///      direct `vm.load` of the single-slot PlayerQuestState (RE-DERIVED via `forge inspect
///      DegenerusQuests storageLayout`: `questPlayerState` root = slot 2; the struct packs into one
///      256-bit word — lastActiveDay u24 byte-3, streak u16 byte-9, afkingActive bool byte-13).
///      Test-only: ZERO contracts/*.sol mutated.
contract V56QuestNonPerturb is DeployProtocol {
    // -------------------------------------------------------------------------
    // DegenerusQuests storage (RE-DERIVED via `forge inspect DegenerusQuests storageLayout`)
    // -------------------------------------------------------------------------

    /// @dev questPlayerState mapping root (address => PlayerQuestState, one packed 256-bit slot).
    uint256 private constant QUEST_PLAYER_STATE_SLOT = 2;

    // PlayerQuestState packed-field byte offsets within its single slot.
    uint256 private constant OFF_LAST_ACTIVE_DAY = 3;  // uint24 lastActiveDay (bytes 3..5)
    uint256 private constant OFF_STREAK = 9;           // uint16 streak        (bytes 9..10)
    uint256 private constant OFF_AFKING_ACTIVE = 13;   // bool   afkingActive  (byte 13)

    // The shipped quest-type tags (DegenerusQuests private constants).
    uint8 private constant QT_MINT_ETH = 1;
    uint8 private constant QT_FLIP = 2;
    uint8 private constant QT_AFFILIATE = 3;
    uint8 private constant QT_DECIMATOR = 5;
    uint8 private constant QT_LOOTBOX = 6;
    uint8 private constant QT_DEGENERETTE_ETH = 7;
    uint8 private constant QT_DEGENERETTE_BURNIE = 8;
    uint8 private constant QT_MINT_BURNIE = 9;

    /// @dev A mint price comfortably above the slot-0 MINT_ETH target so one handleMint completes it.
    ///      Slot-0 target = min(mintPrice * 1, 0.5 ether); a 1-ticket ETH mint at this price clears it.
    uint256 private constant MINT_PRICE = 0.5 ether;

    /// @dev The fixed slot-1 random-quest reward (DegenerusQuests QUEST_RANDOM_REWARD = 200 ether).
    uint256 private constant QUEST_RANDOM_REWARD = 200 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // (a) slot-1 streak-neutral during afking + accessible + NON-afking advances
    // =========================================================================

    /// @notice A NON-afking player's slot-0 (own funded MINT_ETH) completion advances the streak by 1
    ///         (the control: the gate is afkingActive, not a global suppression).
    function testSlot1NonAfkingAdvancesStreakNormally() public {
        address p = makeAddr("nonafk_advance");
        uint32 day = _rollDay(7);

        // Seed a known streak via the shared manual caller, then complete slot 0.
        _awardStreak(p, 5, day);
        uint16 before = _streakViewOf(p);
        assertEq(before, 5, "control: streak seeded to 5");

        _completeSlot0(p, day);

        // NON-afking: the first completion of the day credits the streak (+1).
        assertEq(_streakViewOf(p), 6, "NON-afking: slot-0 completion advances the streak normally (+1)");
        assertFalse(_afkingActiveOf(p), "control player never afking");
    }

    /// @notice During afking, a slot-0 (own funded) quest completion is STREAK-NEUTRAL — the manual
    ///         `state.streak` does NOT advance (the afking compute-on-read owns the streak); the
    ///         completion itself still succeeds (slot stays accessible).
    function testStreakNeutralDuringAfkingSlot0() public {
        address p = makeAddr("afk_neutral0");
        uint32 day = _rollDay(11);

        _awardStreak(p, 5, day);
        _beginAfking(p, day);
        assertTrue(_afkingActiveOf(p), "afking begun (afkingActive set)");
        uint16 before = _streakViewOf(p);

        (, , , bool completed) = _completeSlot0(p, day);

        assertTrue(completed, "Accessible: the slot-0 completion succeeded during afking");
        assertEq(_streakViewOf(p), before, "StreakNeutral: slot-0 completion during afking did NOT advance the streak");
    }

    /// @notice The player's own random/manual slot (slot 1) stays FULLY ACCESSIBLE every day during
    ///         afking — the completion succeeds and pays its QUEST_RANDOM_REWARD — and is STREAK-NEUTRAL
    ///         (the streak does not advance off it while afking).
    function testSlot1AccessibleAndStreakNeutralDuringAfking() public {
        address p = makeAddr("afk_slot1");
        uint32 day = _rollDay(13);

        _awardStreak(p, 5, day);
        _beginAfking(p, day);
        uint16 streakBeforeAny = _streakViewOf(p);

        // Slot 0 must complete first (the slot-1 completion is gated on `completionMask & 1`).
        (, , , bool s0) = _completeSlot0(p, day);
        assertTrue(s0, "slot-0 completed (pre-req for slot-1)");

        // Complete the player's own random/manual slot (slot 1), dispatching the rolled type.
        (uint256 reward, bool s1) = _completeSlot1(p, day);

        assertTrue(s1, "Accessible: the player's own slot-1 (random/manual) quest completed during afking");
        assertEq(reward, QUEST_RANDOM_REWARD, "Accessible: slot-1 paid its full QUEST_RANDOM_REWARD during afking");
        assertEq(
            _streakViewOf(p),
            streakBeforeAny,
            "StreakNeutral: neither slot advanced the streak while afking (afkingActive gates the bump)"
        );
    }

    /// @notice The decisive control pair: the SAME slot-0 completion advances the streak for a
    ///         non-afking player but is neutral for an afking player — proving the gate is exactly
    ///         `afkingActive` (the C3-a non-funded streak dodge stays closed).
    function testStreakNeutralIsGatedByAfkingActiveOnly() public {
        uint32 day = _rollDay(17);

        address afk = makeAddr("gate_afk");
        address human = makeAddr("gate_human");
        _awardStreak(afk, 9, day);
        _awardStreak(human, 9, day);
        _beginAfking(afk, day);

        _completeSlot0(afk, day);
        _completeSlot0(human, day);

        assertEq(_streakViewOf(afk), 9, "afking player: streak-neutral (unchanged)");
        assertEq(_streakViewOf(human), 10, "non-afking player: streak advanced (+1) on the identical completion");
    }

    // =========================================================================
    // (b) cross-caller byte-identity (afking subs present vs absent) + O1 single-credit
    // =========================================================================

    /// @notice `awardQuestStreakBonus` produces a byte-identical PlayerQuestState for a TARGET player
    ///         whether or not OTHER players hold afking subs (have begun afking) — the new shared-core
    ///         entrypoints (beginAfking / finalizeAfking) write only their own player's slot and cannot
    ///         perturb the target's. Asserted on the full packed PlayerQuestState word in two worlds via
    ///         snapshot/revert (NOT a linear re-run).
    function testByteIdentAwardStreakBonusWithAfkingPresentVsAbsent() public {
        address target = makeAddr("byteident_target");
        address other1 = makeAddr("byteident_other1");
        address other2 = makeAddr("byteident_other2");
        uint32 day = _rollDay(13);

        uint256 snap = vm.snapshotState();

        // WORLD-A: NO afking subs present. Run the target's awardQuestStreakBonus path.
        _awardStreak(target, 4, day);
        _awardStreak(target, 3, day);
        uint256 wordA = _questStateWord(target);

        vm.revertToState(snap);

        // WORLD-B: OTHER players hold afking subs (afkingActive set + one mid-finalize), THEN run the
        // IDENTICAL target path.
        _awardStreak(other1, 11, day);
        _beginAfking(other1, day);
        _beginAfking(other2, day);
        _finalizeAfking(other2, 2, day, day); // a sibling finalize write lands before the target path
        _awardStreak(target, 4, day);
        _awardStreak(target, 3, day);
        uint256 wordB = _questStateWord(target);

        assertEq(
            wordB,
            wordA,
            "ByteIdent: the target's PlayerQuestState is byte-identical with afking subs present vs absent"
        );
        assertEq(_streakOf(target), 7, "non-vacuity: the target path actually moved the streak (4+3)");
    }

    /// @notice The manual quest-reward callers (a slot completion + a streak bonus) produce a
    ///         byte-identical target PlayerQuestState across the two worlds (afking siblings present vs
    ///         absent) — the cross-caller boundary does not perturb the existing callers.
    function testByteIdentCrossCallerCompletionWithAfkingPresentVsAbsent() public {
        address target = makeAddr("crosscaller_target");
        address other = makeAddr("crosscaller_other");
        uint32 day = _rollDay(11);

        uint256 snap = vm.snapshotState();

        // WORLD-A: no afking siblings — seed streak, complete slot 0, complete slot 1.
        _awardStreak(target, 6, day);
        _completeSlot0(target, day);
        _completeSlot1(target, day);
        uint256 wordA = _questStateWord(target);
        uint16 streakA = _streakOf(target);
        uint24 lastActiveA = _lastActiveDayOf(target);

        vm.revertToState(snap);

        // WORLD-B: an afking sibling is active across the identical target path.
        _awardStreak(other, 8, day);
        _beginAfking(other, day);
        _awardStreak(target, 6, day);
        _completeSlot0(target, day);
        _completeSlot1(target, day);
        uint256 wordB = _questStateWord(target);

        assertEq(wordB, wordA, "CrossCaller: byte-identical target PlayerQuestState (afking sibling present vs absent)");
        assertEq(streakA, 7, "non-vacuity: the non-afking target advanced its streak (6 -> 7)");
        assertEq(lastActiveA, uint24(day), "non-vacuity: the slot-0 completion bumped lastActiveDay");
    }

    /// @notice O1 single-credit: a completed LOOTBOX quest credits its reward exactly once. In the v56
    ///         fix the lootbox-quest reward is RETURNED to the caller (credited once there) and is NOT
    ///         internally creditFlipped — so the handler returns the single QUEST_RANDOM_REWARD and the
    ///         player's accrued flip balance does NOT move by the lootbox reward inside the handler (no
    ///         internal double-credit). Holds identically whether or not afking siblings are present.
    function testO1LootboxSingleCreditAcrossTwoWorlds() public {
        address target = makeAddr("o1_target");
        address other = makeAddr("o1_other");
        uint32 day = _rollDay(4); // slot-1 rolls LOOTBOX (the O1 region)
        {
            QuestInfo[2] memory active = quests.getActiveQuests();
            assertEq(active[1].questType, QT_LOOTBOX, "fixture: day-4 slot-1 is LOOTBOX (the O1 region)");
        }

        uint256 snap = vm.snapshotState();

        // WORLD-A: no afking siblings.
        uint256 rewardA = _completeLootboxSlot1(target, day);
        uint256 internalCreditA = coinflip.coinflipAmount(target);

        vm.revertToState(snap);

        // WORLD-B: an afking sibling is active.
        _beginAfking(other, day);
        uint256 rewardB = _completeLootboxSlot1(target, day);
        uint256 internalCreditB = coinflip.coinflipAmount(target);

        // The lootbox reward is RETURNED once (the single credit the caller applies) and is NOT
        // internally creditFlipped — proving the O1 double-credit is not re-introduced.
        assertEq(rewardA, QUEST_RANDOM_REWARD, "O1: WORLD-A lootbox reward returned exactly once (single QUEST_RANDOM_REWARD)");
        assertEq(rewardB, rewardA, "SingleCredit: identical returned reward with afking present vs absent");
        assertEq(internalCreditA, 0, "O1: lootbox reward NOT internally creditFlipped (returned to caller only)");
        assertEq(internalCreditB, internalCreditA, "SingleCredit: no internal credit in either world");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Roll the daily quest set for `day` (slot 0 = MINT_ETH; slot 1 = entropy-derived), pranked
    ///      as GAME. Returns the day so callers thread the same currentDay into the handlers.
    function _rollDay(uint32 day) internal returns (uint32) {
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(uint24(day), uint256(keccak256(abi.encode(day, "v56qnp"))));
        return day;
    }

    /// @dev Seed a player's streak via the shared manual/bingo/degenerette/boon caller.
    function _awardStreak(address player, uint16 amount, uint32 day) internal {
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakBonus(player, amount, uint24(day));
    }

    /// @dev Flip the afking flag for a player (snapshots the synced streak), pranked as GAME.
    function _beginAfking(address player, uint32 day) internal {
        vm.prank(ContractAddresses.GAME);
        quests.beginAfking(player, uint24(day));
    }

    /// @dev End a player's afking run (hands the earned streak back), pranked as GAME.
    function _finalizeAfking(address player, uint24 earned, uint32 coveredDay, uint32 day) internal {
        vm.prank(ContractAddresses.GAME);
        quests.finalizeAfking(player, earned, uint24(coveredDay), uint24(day));
    }

    /// @dev Complete a LOOTBOX slot-1 quest via the COIN-gated handlePurchase (the O1 region) with the
    ///      lootbox leg ISOLATED: slot 0 (MINT_ETH) is completed first in a separate handleMint, then a
    ///      lootbox-only handlePurchase (ethMintSpendWei = 0) clears the slot-1 LOOTBOX target so the
    ///      returned reward is PURELY the single lootbox reward (the value the caller credits once).
    function _completeLootboxSlot1(address player, uint32 /*day*/) internal returns (uint256 reward) {
        vm.prank(ContractAddresses.COIN);
        quests.handleMint(player, 1, true, MINT_PRICE); // slot-0 pre-req (its reward is returned, not relevant here)
        vm.prank(ContractAddresses.COIN);
        (reward, , , ) = quests.handlePurchase(player, 0, 0, 1 ether, MINT_PRICE, MINT_PRICE);
    }

    /// @dev Complete slot 0 (MINT_ETH) via the COIN-gated handleMint with a 1-ticket ETH mint sized
    ///      above the slot-0 target. Returns the handler tuple.
    function _completeSlot0(address player, uint32 /*day*/)
        internal
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        vm.prank(ContractAddresses.COIN);
        (reward, questType, streak, completed) = quests.handleMint(player, 1, true, MINT_PRICE);
    }

    /// @dev Complete the player's own slot 1 by reading its rolled type and routing the matching
    ///      COIN-gated handler with a delta sized to clear the target.
    function _completeSlot1(address player, uint32 /*day*/) internal returns (uint256 reward, bool completed) {
        QuestInfo[2] memory active = quests.getActiveQuests();
        uint8 t = active[1].questType;
        uint8 qt;
        uint32 s;
        if (t == QT_FLIP) {
            vm.prank(ContractAddresses.COIN);
            (reward, qt, s, completed) = quests.handleFlip(player, 100 ether);
        } else if (t == QT_DECIMATOR) {
            vm.prank(ContractAddresses.COIN);
            (reward, qt, s, completed) = quests.handleDecimator(player, 100 ether);
        } else if (t == QT_AFFILIATE) {
            vm.prank(ContractAddresses.COIN);
            (reward, qt, s, completed) = quests.handleAffiliate(player, 100 ether);
        } else if (t == QT_MINT_BURNIE) {
            vm.prank(ContractAddresses.COIN);
            (reward, qt, s, completed) = quests.handleMint(player, 100, false, MINT_PRICE);
        } else {
            // LOOTBOX / DEGENERETTE_ETH / DEGENERETTE_BURNIE / MINT_ETH share the purchase path; an
            // ETH-mint spend + lootbox spend covers the ETH-denominated slot-1 types, a BURNIE-mint
            // qty covers DEGENERETTE_BURNIE. handlePurchase credits the lootbox reward via the caller,
            // so the returned reward is the slot's QUEST_RANDOM_REWARD.
            vm.prank(ContractAddresses.COIN);
            (reward, qt, s, completed) = quests.handlePurchase(player, 1 ether, 100, 1 ether, MINT_PRICE, MINT_PRICE);
        }
    }

    // ---- PlayerQuestState reads (slot 2 mapping; single packed word) ----

    function _questStateWord(address who) internal view returns (uint256) {
        return uint256(vm.load(ContractAddresses.QUESTS, keccak256(abi.encode(who, QUEST_PLAYER_STATE_SLOT))));
    }

    function _streakOf(address who) internal view returns (uint16) {
        return uint16(_questStateWord(who) >> (OFF_STREAK * 8));
    }

    function _afkingActiveOf(address who) internal view returns (bool) {
        return uint8(_questStateWord(who) >> (OFF_AFKING_ACTIVE * 8)) != 0;
    }

    function _lastActiveDayOf(address who) internal view returns (uint24) {
        return uint24(_questStateWord(who) >> (OFF_LAST_ACTIVE_DAY * 8));
    }

    /// @dev The streak as the public view reports it (cross-checks the direct slot read).
    function _streakViewOf(address who) internal view returns (uint16) {
        (uint32 streak, , , ) = quests.playerQuestStates(who);
        return uint16(streak);
    }
}
