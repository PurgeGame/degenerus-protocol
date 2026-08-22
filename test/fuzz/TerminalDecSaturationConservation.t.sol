// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title TerminalDecSaturationConservation — bucket aggregate mirrors stored weight
/// @notice Pins the conservation law of recordTerminalDecBurn: every burn moves
///         terminalDecBucketBurnTotal by exactly the delta the player's stored
///         weightedBurn actually rose by, so the claim-share denominator always
///         equals the sum of stored (claimable) weights:
///           1. BELOW-CAP — ordinary burns credit the aggregate 1:1 with the store.
///           2. AT-CAP    — a burn landing on a saturated uint88 weightedBurn adds
///                          nothing to the aggregate (no phantom denominator weight).
///           3. CROSSING  — a burn that crosses the ceiling credits only the
///                          clamped remainder, and the emitted weightedAmount is
///                          that credited delta.
///
/// @dev recordTerminalDecBurn is driven directly with vm.prank(COIN) (the FLIP
///      entrypoint's only call site). Saturation states are installed via vm.store
///      on the packed TerminalDecBet slot (weightedBurn @ bits [80..168)), with the
///      paired aggregate seeded to the same value so the invariant holds pre-burn.
contract TerminalDecSaturationConservation is DeployProtocol {
    // forge inspect DegenerusGame storageLayout:
    uint256 internal constant SLOT_TERMINAL_DEC_BETS = 47; // mapping(address => TerminalDecBet)
    uint256 internal constant SLOT_TERMINAL_DEC_BUCKET_TOTAL = 48; // mapping(bytes32 => uint256)

    uint88 internal constant WEIGHT_MAX = type(uint88).max;
    uint24 internal constant LVL = 0; // fresh game: level 0, 365-day idle window open

    address internal player;

    event TerminalDecBurnRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint8 bucket,
        uint8 subBucket,
        uint256 effectiveAmount,
        uint256 weightedAmount,
        uint256 timeMultBps
    );

    function setUp() public {
        _deployProtocol();
        player = makeAddr("terminal_dec_player");
    }

    // ----------------------------------------------------------------------
    //                       storage helpers
    // ----------------------------------------------------------------------

    function _betSlot() internal view returns (bytes32) {
        return keccak256(abi.encode(player, SLOT_TERMINAL_DEC_BETS));
    }

    /// @dev Packed TerminalDecBet: totalBurn u80 | weightedBurn u88 | bucket u8
    ///      | subBucket u8 | burnLevel u48 | boosted bool.
    function _bet()
        internal
        view
        returns (uint256 weightedBurn, uint8 bucket, uint8 subBucket)
    {
        uint256 w = uint256(vm.load(address(game), _betSlot()));
        weightedBurn = (w >> 80) & ((uint256(1) << 88) - 1);
        bucket = uint8(w >> 168);
        subBucket = uint8(w >> 176);
    }

    /// @dev Overwrite only the weightedBurn field, preserving siblings.
    function _setWeightedBurn(uint88 v) internal {
        uint256 w = uint256(vm.load(address(game), _betSlot()));
        uint256 mask = ((uint256(1) << 88) - 1) << 80;
        w = (w & ~mask) | (uint256(v) << 80);
        vm.store(address(game), _betSlot(), bytes32(w));
    }

    function _aggSlot(uint8 bucket, uint8 subBucket) internal pure returns (bytes32) {
        bytes32 key = keccak256(abi.encode(LVL, bucket, subBucket));
        return keccak256(abi.encode(key, SLOT_TERMINAL_DEC_BUCKET_TOTAL));
    }

    function _agg(uint8 bucket, uint8 subBucket) internal view returns (uint256) {
        return uint256(vm.load(address(game), _aggSlot(bucket, subBucket)));
    }

    function _burnAsCoin(uint256 baseAmount) internal {
        vm.prank(ContractAddresses.COIN);
        game.recordTerminalDecBurn(player, LVL, baseAmount);
    }

    // ----------------------------------------------------------------------
    //                       tests
    // ----------------------------------------------------------------------

    /// @notice Ordinary burns keep aggregate == stored weight, burn after burn.
    function test_belowCap_aggregateMatchesStoredWeight() public {
        _burnAsCoin(10_000 ether);
        (uint256 stored, uint8 bucket, uint8 sub) = _bet();
        assertGt(stored, 0, "first burn recorded no weight");
        assertEq(_agg(bucket, sub), stored, "aggregate != stored after first burn");

        _burnAsCoin(3_000 ether);
        (uint256 stored2, , ) = _bet();
        assertGt(stored2, stored, "second burn recorded no weight");
        assertEq(_agg(bucket, sub), stored2, "aggregate != stored after second burn");
    }

    /// @notice A burn onto a saturated weightedBurn adds no aggregate weight.
    function test_atCap_burnAddsNoPhantomAggregateWeight() public {
        _burnAsCoin(10_000 ether);
        (, uint8 bucket, uint8 sub) = _bet();
        _setWeightedBurn(WEIGHT_MAX);
        vm.store(address(game), _aggSlot(bucket, sub), bytes32(uint256(WEIGHT_MAX)));

        _burnAsCoin(50_000 ether);

        (uint256 stored, , ) = _bet();
        assertEq(stored, WEIGHT_MAX, "stored weight moved past the cap");
        assertEq(_agg(bucket, sub), WEIGHT_MAX, "aggregate grew past the sum of stored weights");
    }

    /// @notice A cap-crossing burn credits exactly the clamped remainder and
    ///         emits that delta as weightedAmount.
    function test_crossingCap_aggregateGrowsByClampedDeltaOnly() public {
        _burnAsCoin(10_000 ether);
        (, uint8 bucket, uint8 sub) = _bet();
        uint88 nearCap = WEIGHT_MAX - 1e18;
        _setWeightedBurn(nearCap);
        vm.store(address(game), _aggSlot(bucket, sub), bytes32(uint256(nearCap)));

        vm.recordLogs();
        _burnAsCoin(50_000 ether);

        (uint256 stored, , ) = _bet();
        assertEq(stored, WEIGHT_MAX, "crossing burn did not saturate the store");
        assertEq(_agg(bucket, sub), WEIGHT_MAX, "aggregate != stored after crossing burn");

        // The emitted weightedAmount is the credited delta, not the raw amount.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic0 = keccak256(
            "TerminalDecBurnRecorded(address,uint24,uint8,uint8,uint256,uint256,uint256)"
        );
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != topic0) continue;
            (, , , uint256 weightedAmount, ) = abi.decode(
                logs[i].data,
                (uint256, uint256, uint256, uint256, uint256)
            );
            assertEq(weightedAmount, uint256(1e18), "emitted weight != credited delta");
            found = true;
        }
        assertTrue(found, "TerminalDecBurnRecorded not emitted");
    }
}
