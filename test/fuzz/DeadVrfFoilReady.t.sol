// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {claimableBalance} from "../helpers/ClaimableBalance.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "./helpers/DeadVrfSeeder.sol";

/// @dev Etch overlay: the foil state a cohort swap leaves when the read cohort it swaps out was
///      only part-drained. Every measured call runs the production Game runtime.
contract DeadVrfFoilReadySeeder is DeadVrfSeeder {
    /// @dev Mark `player`'s pack record of `lvl` ready, as `_resolveFoilBuyer` does.
    function seedReadyRecord(uint24 lvl, address player) external {
        uint32 id = _seedWallet(player);
        foilRecord[lvl & 3][id] = (uint256(lvl) << _FOIL_LEVEL_SHIFT) | _FOIL_READY;
    }

    /// @dev File `player`'s pack of `lvl`: the ready record plus its sixteen tickets in `trait`.
    function seedFiled(uint24 lvl, uint8 trait, address player) external {
        uint32 id = _seedWallet(player);
        foilRecord[lvl & 3][id] = (uint256(lvl) << _FOIL_LEVEL_SHIFT) | _FOIL_READY;
        _seedBucket(lvl, trait, player, FOIL_PACK_ENTRIES);
    }

    function setFoilCursor(uint32 cursor) external {
        foilCursor = cursor;
    }

    /// @dev The body of `_swapFoilSlot` (DegenerusGameRngUtils).
    function swapFoil() external {
        foilWriteSlot = !foilWriteSlot;
        foilCursor = 0;
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
        (foilWriteCount, foilReadCount) = (foilReadCount, foilWriteCount);
    }

    function foilReadKey() external view returns (uint24) {
        return _foilReadKey();
    }
}

/// @notice Deterministic ending: a foil pack whose sixteen tickets are already in the trait
///         buckets is counted and paid through those tickets only, wherever the cohort cursor
///         stands.
contract DeadVrfFoilReadyTest is DeployProtocol {
    uint24 private constant LVL = 5000; // purchase phase: the terminal ticket level is LVL + 1
    uint24 private constant TLVL = LVL + 1;
    uint8 private constant TRAIT = 7;
    uint256 private constant PACK_WEIGHT = 1600; // FOIL_PACK_ENTRIES * QTY_SCALE

    bytes private realCode;
    address private amy = makeAddr("amy");
    address private ben = makeAddr("ben");
    address private cal = makeAddr("cal");
    address private dan = makeAddr("dan");

    uint24 private cohort;
    uint256 private amyIdx;
    uint256 private benIdx;
    uint256 private calIdx;
    uint256 private danIdx;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 200 days);
        vm.deal(address(game), 100 ether);
        realCode = address(game).code;
    }

    function _seeder() private returns (DeadVrfFoilReadySeeder s) {
        vm.etch(address(game), type(DeadVrfFoilReadySeeder).runtimeCode);
        s = DeadVrfFoilReadySeeder(payable(address(game)));
    }

    function _restore() private {
        vm.etch(address(game), realCode);
        uint256 packed = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(
            address(coinflip),
            bytes32(uint256(4)),
            bytes32((packed & ~(uint256(0xffffff) << 176)) | (uint256(game.currentDayView_g542950()) << 176))
        );
    }

    /// @dev The read cohort holds four packs in order: amy's (terminal level), ben's (terminal
    ///      level), cal's (another level) and dan's (terminal level). One drain batch filed amy's
    ///      pack and stopped, so the cursor stands at 1. cal's record of her own level and dan's
    ///      record of an earlier level are ready; neither names the terminal level.
    function _seedPartDrained(bool swapped) private {
        DeadVrfFoilReadySeeder s = _seeder();
        s.seedDeadStall(LVL);
        cohort = s.foilReadKey();
        amyIdx = s.seedFoil(TLVL, cohort, amy);
        benIdx = s.seedFoil(TLVL, cohort, ben);
        calIdx = s.seedFoil(TLVL - 2, cohort, cal);
        danIdx = s.seedFoil(TLVL, cohort, dan);
        s.seedFiled(TLVL, TRAIT, amy);
        s.seedReadyRecord(TLVL - 2, cal);
        s.seedReadyRecord(TLVL - 1, dan);
        s.setFoilCursor(1);
        if (swapped) s.swapFoil();
        _restore();
    }

    function _endGame() private {
        for (uint256 i; i < 20 && !game.gameOver(); ++i) game.mineRun(0);
        assertTrue(game.gameOver(), "dead ending reached game over");
    }

    function _state() private returns (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits, uint256 left) {
        (pot, total, created, uncreated, traits, left) = _seeder().deadState();
        _restore();
    }

    function _packRef(uint256 idx) private view returns (uint256) {
        return (uint256(2) << 248) | (uint256(cohort) << 64) | idx;
    }

    function _one(uint256 ref) private pure returns (uint256[] memory refs) {
        refs = new uint256[](1);
        refs[0] = ref;
    }

    function _checkSplit() private {
        assertTrue(game.livenessTriggered(), "request unanswered 15 days");
        _endGame();
        (uint256 pot, uint256 total) = _checkTally();
        _checkClaims(pot, total);
        (,,,,, uint256 left) = _state();
        assertEq(left, 0, "every uncreated unit claimed exactly once");
    }

    function _checkTally() private returns (uint256 pot, uint256 total) {
        uint256 created;
        uint256 uncreated;
        uint256 traits;
        (pot, total, created, uncreated, traits,) = _state();
        assertGt(pot, 0, "a pot was fixed");
        assertEq(created, 16, "amy's sixteen filed tickets");
        assertEq(traits, 1, "one non-empty trait");
        assertEq(uncreated, 2 * PACK_WEIGHT, "ben's and dan's packs only: amy's is filed, cal's is another level");
        assertEq(total, 16 * 100 + 2 * PACK_WEIGHT, "total weight");
    }

    function _checkClaims(uint256 pot, uint256 total) private {
        uint32 amyId = game.walletIdOf_g3120(amy);
        uint32 benId = game.walletIdOf_g3120(ben);
        uint32 calId = game.walletIdOf_g3120(cal);
        uint32 danId = game.walletIdOf_g3120(dan);

        // amy's pack word pays nothing; her sixteen tickets pay the created share.
        vm.expectRevert(bytes4(keccak256("E()")));
        game.claimDeadVrf(amyId, _one(_packRef(amyIdx)));
        uint256[] memory tickets = new uint256[](16);
        for (uint256 k; k < 16; ++k) tickets[k] = (uint256(TRAIT) << 64) | k;
        game.claimDeadVrf(amyId, tickets);
        // One non-empty trait holding sixteen tickets: the created share is pot * 1600 / total.
        uint256 perTrait = (pot * 16 * 100) / total;
        assertEq(claimableBalance(game, amy), 16 * (perTrait / 16), "amy: the whole created share, once");

        // cal's pack is not of the terminal level.
        vm.expectRevert(bytes4(keccak256("E()")));
        game.claimDeadVrf(calId, _one(_packRef(calIdx)));

        game.claimDeadVrf(benId, _one(_packRef(benIdx)));
        assertEq(claimableBalance(game, ben), (pot * PACK_WEIGHT) / total, "ben: the average for a foil pack");
        // dan's ready record names another level, so his terminal-level pack still counts.
        game.claimDeadVrf(danId, _one(_packRef(danIdx)));
        assertEq(claimableBalance(game, dan), (pot * PACK_WEIGHT) / total, "dan: the average for a foil pack");
        vm.expectRevert(bytes4(keccak256("E()")));
        game.claimDeadVrf(benId, _one(_packRef(benIdx))); // pack word zeroed

        uint256 paid = claimableBalance(game, amy) + claimableBalance(game, ben) + claimableBalance(game, dan);
        assertLe(paid, pot, "never more than the pot");
        assertLt(pot - paid, 32, "only rounding dust left");
    }

    /// @dev The cohort was swapped to the write side with its cursor reset: only the ready mark
    ///      still tells amy's filed pack from an unfiled one.
    function test_filedPackBehindAResetCursorCountsOnce() public {
        _seedPartDrained(true);
        _checkSplit();
    }

    /// @dev No swap: the cursor already excludes amy's pack, and the ready mark agrees with it.
    function test_filedPackBehindTheCursorCountsOnce() public {
        _seedPartDrained(false);
        _checkSplit();
    }
}
