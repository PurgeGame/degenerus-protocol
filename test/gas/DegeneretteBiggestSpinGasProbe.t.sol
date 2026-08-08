// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @title DegeneretteBiggestSpinGasProbe — what the biggest-spin record costs at placement,
///        and what the 1 ETH entry gate buys back.
///
/// @dev EIP-2929 warm/cold state persists for a whole transaction, and a Foundry test body
///      IS one transaction — so measuring both shapes inside one test would report the
///      record slot as WARM on the second read and understate the cost by ~2,000 gas. Real
///      placements are one-per-transaction, where slot 16 is always COLD. Each shape
///      therefore gets its own test (its own transaction), with identical warm-up so only
///      the record path differs:
///        A. sub-floor bet   — the gate short-circuits, slot 16 is never touched. This is
///                             the pre-feature cost plus one comparison.
///        B. above-floor bet — pays the COLD SLOAD of slot 16 and ratchets nothing.
///        C. above-floor bet that beats the record by a tenth — adds the SSTORE, the
///           accrual arithmetic and two events. The worst case.
///      The standing record is planted with vm.store in setUp (a separate transaction), so
///      the test body starts with slot 16 genuinely cold.
contract DegeneretteBiggestSpinGasProbeTest is DeployProtocol {
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant BIGGEST_SPIN_SLOT = 16;
    uint256 private constant RECORD_SHIFT = 96;
    uint256 private constant RECORD_DAY_SHIFT = 224;

    uint8 private constant CURRENCY_ETH = 0;
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);

        player = makeAddr("gas_probe_player");
        vm.deal(player, 1_000_000 ether);
        vm.deal(address(game), 100_000 ether);

        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        uint256 pools = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        pools = (pools & ~(((uint256(1) << 104) - 1) << 104)) | (uint256(50_000 ether) << 104);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(pools));

        // Plant a standing record well above every probe, so B ratchets nothing. Written
        // here rather than via a placement so the test body never pre-warms slot 16.
        uint256 rec = uint256(vm.load(address(game), bytes32(BIGGEST_SPIN_SLOT)));
        rec |= (uint256(1_000 ether) << RECORD_SHIFT) | (uint256(1) << RECORD_DAY_SHIFT);
        vm.store(address(game), bytes32(BIGGEST_SPIN_SLOT), bytes32(rec));
    }

    function testGasA_subFloorBet() public {
        _warmUp();
        emit log_named_uint("A sub-floor bet (gate skips slot 16)", _measure(MIN_BET_ETH));
    }

    function testGasB_aboveFloorNoRecord() public {
        _warmUp();
        emit log_named_uint("B above-floor, cold record SLOAD", _measure(2 ether));
    }

    function testGasC_aboveFloorRatchetsAndClaims() public {
        _warmUp();
        emit log_named_uint("C above-floor, ratchets AND claims", _measure(2_000 ether));
    }

    /// @notice The gate's actual contract: a sub-floor bet must not touch the record slot at
    ///         all. Asserted against the recorded access set rather than a gas threshold, so
    ///         it stays meaningful when unrelated costs move.
    function testSubFloorBetNeverAccessesRecordSlot() public {
        _warmUp();

        vm.record();
        _place(MIN_BET_ETH);
        (bytes32[] memory subReads, bytes32[] memory subWrites) = vm.accesses(address(game));
        assertFalse(_touches(subReads, subWrites), "a sub-floor bet must not touch slot 16");

        vm.record();
        _place(2 ether);
        (bytes32[] memory bigReads, bytes32[] memory bigWrites) = vm.accesses(address(game));
        assertTrue(_touches(bigReads, bigWrites), "an above-floor bet does consult slot 16");
    }

    function _touches(bytes32[] memory reads, bytes32[] memory writes)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < reads.length; ++i) {
            if (uint256(reads[i]) == BIGGEST_SPIN_SLOT) return true;
        }
        for (uint256 i; i < writes.length; ++i) {
            if (uint256(writes[i]) == BIGGEST_SPIN_SLOT) return true;
        }
        return false;
    }

    /// @dev Identical in all three: two sub-floor placements so the per-player nonce, the
    ///      day's hero-wager bucket and the pool slots are warm, and slot 16 is untouched.
    function _warmUp() internal {
        _place(MIN_BET_ETH);
        _place(MIN_BET_ETH);
    }

    function _measure(uint256 perSpin) internal returns (uint256 used) {
        vm.prank(player);
        uint256 before = gasleft();
        game.placeDegeneretteBet{value: perSpin}(
            address(0), CURRENCY_ETH, uint128(perSpin), 1, 0x00010203, 0
        );
        used = before - gasleft();
    }

    function _place(uint256 perSpin) internal {
        vm.prank(player);
        game.placeDegeneretteBet{value: perSpin}(
            address(0), CURRENCY_ETH, uint128(perSpin), 1, 0x00010203, 0
        );
    }
}
