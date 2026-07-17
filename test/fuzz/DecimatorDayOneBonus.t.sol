// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title DecimatorDayOneBonus — 1.2x weight while the day-one latch is armed
/// @notice Pins the day-one decimator weight bonus in recordDecBurn:
///           1. ARMED       — a burn while decDayOneActive is set records 1.2x weight
///                            (multBps 10_000 -> 12_000), even at zero activity score.
///           2. UNARMED     — a burn with the latch clear (the fresh-deploy default)
///                            records face weight, so no bonus leaks before the first
///                            window opens or after the next-day request clears it.
///           3. STACKS      — the bonus multiplies the activity curve: maxed score
///                            17_833 bps records (17_833 * 12_000) / 10_000 = 21_399 bps.
///           4. CAP-BOUNDED — the boosted accrual stays inside DECIMATOR_MULTIPLIER_CAP
///                            (200k FLIP); overflow burns count at face value.
///
/// @dev recordDecBurn is driven directly with vm.prank(COIN) (the FLIP entrypoint's only
///      call site), with the decDayOneActive latch installed via vm.store (slot 0 byte 31).
///      Weights are read back from decBurn[lvl][player].burn. The latch's set site (the
///      x4/x99 window-open request) and clear site (the next fresh daily request) live in
///      AdvanceModule._finalizeRngRequest and are covered by inspection + lifecycle suites.
contract DecimatorDayOneBonus is DeployProtocol {
    // forge inspect DegenerusGame storageLayout:
    uint256 internal constant SLOT_HEADER = 0; // packed flags; decDayOneActive @ byte 31
    uint256 internal constant SLOT_DEC_BURN = 40; // mapping(uint24 => mapping(address => DecBet))

    uint256 internal constant BPS = 10_000;
    uint256 internal constant DAY_ONE_BONUS_BPS = 12_000; // mirror of the module constant
    uint256 internal constant MULT_MAX_BPS = 17_833; // ActivityCurveLib.MULT_MAX_BPS
    uint256 internal constant MULTIPLIER_CAP = 200_000 ether; // DECIMATOR_MULTIPLIER_CAP

    uint24 internal constant LVL = 5;
    uint8 internal constant BUCKET = 5;

    address internal player;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("dec_player");
    }

    // ----------------------------------------------------------------------
    //                       storage helpers
    // ----------------------------------------------------------------------

    /// @dev Arm/disarm the decDayOneActive latch (slot 0, byte 31), preserving siblings.
    function _setDayOneLatch(bool armed) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        uint256 mask = uint256(0xFF) << (31 * 8);
        w = armed ? (w | (uint256(1) << (31 * 8))) : (w & ~mask);
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(w));
    }

    /// @dev decBurn[lvl][player].burn (low 192 bits of the packed DecBet slot).
    function _recordedBurn() internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(LVL), SLOT_DEC_BURN));
        bytes32 slot = keccak256(abi.encode(player, uint256(inner)));
        return uint256(vm.load(address(game), slot)) & ((uint256(1) << 192) - 1);
    }

    function _burnAsCoin(uint256 baseAmount, uint256 multBps) internal {
        vm.prank(ContractAddresses.COIN);
        game.recordDecBurn(player, LVL, BUCKET, baseAmount, multBps);
    }

    // ----------------------------------------------------------------------
    //                       tests
    // ----------------------------------------------------------------------

    /// @notice Armed latch + zero activity score records 1.2x weight.
    function test_armedLatchCarries20PercentBonus() public {
        _setDayOneLatch(true);
        _burnAsCoin(10_000 ether, BPS); // zero-score multiplier = 1.0x
        assertEq(_recordedBurn(), 12_000 ether, "armed weight != 1.2x");
    }

    /// @notice Fresh-deploy default (latch clear) records face weight — no bonus
    ///         leaks before the first window opens or after the clear.
    function test_unarmedLatchRecordsFaceWeight() public {
        _burnAsCoin(10_000 ether, BPS);
        assertEq(_recordedBurn(), 10_000 ether, "unarmed weight != face");
    }

    /// @notice The day-one bonus multiplies the activity curve's multiplier.
    function test_bonusStacksWithActivityMultiplier() public {
        _setDayOneLatch(true);
        _burnAsCoin(10_000 ether, MULT_MAX_BPS);
        // multBps = (17_833 * 12_000) / 10_000 = 21_399 (floor); weight = 10_000 * 2.1399.
        uint256 expected = (10_000 ether * ((MULT_MAX_BPS * DAY_ONE_BONUS_BPS) / BPS)) / BPS;
        assertEq(_recordedBurn(), expected, "stacked weight mismatch");
    }

    /// @notice The 200k multiplied-accrual cap bounds the boosted weight: beyond the
    ///         cap allowance, the remainder of the burn counts at face value.
    function test_bonusBoundedByMultiplierCap() public {
        _setDayOneLatch(true);
        uint256 base = 300_000 ether;
        _burnAsCoin(base, BPS);
        // Mirror of _decEffectiveAmount with multBps = 12_000, prevBurn = 0:
        uint256 boosted = (base * DAY_ONE_BONUS_BPS) / BPS; // 360k > 200k cap
        assertGt(boosted, MULTIPLIER_CAP, "test premise: burn must exceed cap");
        uint256 maxMultBase = (MULTIPLIER_CAP * BPS) / DAY_ONE_BONUS_BPS;
        uint256 expected = (maxMultBase * DAY_ONE_BONUS_BPS) / BPS + (base - maxMultBase);
        assertEq(_recordedBurn(), expected, "cap-bounded weight mismatch");
    }
}
