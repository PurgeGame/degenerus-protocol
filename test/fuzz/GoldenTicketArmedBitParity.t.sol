// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GoldenTicketHarness, CoinflipRecorder, WwxrpRecorder, ReturnZeroSink} from "./GoldenTicketArmResolve.t.sol";

/// @title GoldenTicketArmedBitParity -- the armed flag is bit 189, not the winner's address parity
/// @notice An armed golden ticket resolves on the first main board after its arm draw. The flag
///         lives at bit 189 of the packed slot, above the winner's address in the low 160 bits.
///         Mutation v78 rewrote the read as `(g * 189) & 1` — bit zero of the winner's address —
///         and survived because every fixture winner happened to have an odd address. Here the
///         only holder of each bucket has an EVEN address, so a parity read says "not armed" and
///         the ticket would never resolve.
contract GoldenTicketArmedBitParity is Test {
    GoldenTicketHarness internal h;

    uint24 internal constant LVL = 5;
    uint24 internal constant ARM_IDX = 10;

    function setUp() public {
        h = new GoldenTicketHarness();
        vm.etch(ContractAddresses.COINFLIP, address(new CoinflipRecorder()).code);
        vm.etch(ContractAddresses.WWXRP, address(new WwxrpRecorder()).code);
        ReturnZeroSink sink = new ReturnZeroSink();
        vm.etch(ContractAddresses.STETH_TOKEN, address(sink).code);
        vm.etch(ContractAddresses.JACKPOTS, address(sink).code);
        h.setLevel(LVL);
        h.setJackpotCounter(1);
        h.setDailyIdx(ARM_IDX);
        h.setCurrentPool(1000 ether);
        h.setPools(200 ether, 1000 ether);
    }

    function _word(uint8[4] memory colors, uint8[4] memory syms, uint256 salt) internal pure returns (uint256 w) {
        for (uint256 i; i < 4; ++i) {
            w |= (uint256(colors[i]) << 3 | uint256(syms[i])) << (i * 6);
        }
        w |= salt << 24;
    }

    /// @dev One holder per winning bucket; `seedBucket` pushes `base + 1`, so an odd base seats
    ///      an even address.
    function _seedSingles(uint256 word, uint160 base) internal {
        for (uint8 i; i < 4; ++i) {
            uint8 trait = uint8(uint256(i) * 64 + ((word >> (uint256(i) * 6)) & 0x3F));
            h.seedBucket(LVL, trait, 1, base + uint160(i) * 100);
        }
    }

    function _resolves(uint160 base) internal returns (bool found, address winner) {
        uint256 arm = _word([7, 7, 7, 7], [1, 2, 3, 4], 0xA11CE);
        _seedSingles(arm, base);
        h.payDailyJackpot(true, LVL, arm);
        uint256 g = h.goldenTicketRaw();
        assertEq((g >> 189) & 1, 1, "armed");
        winner = address(uint160(g));

        h.setDailyIdx(ARM_IDX + 1);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, _word([1, 2, 3, 4], [1, 2, 3, 4], 0xBEEF));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) found = true;
        }
        assertEq((h.goldenTicketRaw() >> 189) & 1, 0, "the arm is spent by the resolve");
    }

    function test_evenAddressedWinnerStillResolves() public {
        (bool found, address winner) = _resolves(0x1001);
        assertEq(uint160(winner) & 1, 0, "fixture: the armed winner's address is even");
        assertTrue(found, "an even-addressed winner's ticket resolves on the next board");
    }

    function test_oddAddressedWinnerResolves() public {
        (bool found, address winner) = _resolves(0x1000);
        assertEq(uint160(winner) & 1, 1, "fixture: the armed winner's address is odd");
        assertTrue(found, "an odd-addressed winner's ticket resolves on the next board");
    }
}
