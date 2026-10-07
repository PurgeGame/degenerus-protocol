// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {JackpotBoardFixtures} from "./helpers/JackpotBoardFixtures.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {GoldenTicketHarness, CoinflipRecorder, WwxrpRecorder, ReturnZeroSink} from "./GoldenTicketArmResolve.t.sol";

contract GoldenTicketParityHarness is GoldenTicketHarness {
    function registerForParity(address player) external returns (uint32) {
        return _seedWallet(player);
    }
}

/// @notice The armed flag at bit 189 must resolve both even and odd winner IDs.
/// A parity mutation reading bit zero must not substitute for the independent flag.
contract GoldenTicketArmedBitParity is Test {
    GoldenTicketParityHarness internal h;

    uint24 internal constant LVL = 5;
    uint24 internal constant ARM_IDX = 10;

    function setUp() public {
        h = new GoldenTicketParityHarness();
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
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
        return JackpotBoardFixtures.wordFor(colors, syms, salt == 0xBEEF || salt == 0xFEED);
    }

    /// @dev Odd base selects even IDs: reserve ID 1, then interleave one unused ID per holder.
    /// Even base starts at ID 1 and interleaves the same way, yielding only odd candidates.
    function _seedSingles(uint256 word, uint160 base) internal {
        if (base & 1 != 0) h.registerForParity(address(0xF00D));
        for (uint8 i; i < 4; ++i) {
            uint8 trait = JackpotBucketLib.getRandomTraits(word)[i];
            h.seedBucket(LVL, trait, 1, base + uint160(i) * 100);
            h.registerForParity(address(uint160(0xF000) + uint160(i)));
        }
    }

    function _resolves(uint160 base) internal returns (bool found, uint32 winner) {
        uint256 arm = _word([7, 7, 7, 7], [1, 2, 3, 4], 0xA11CE);
        _seedSingles(arm, base);
        h.runDailyJackpot(true, LVL, arm, gasleft());
        uint256 g = h.goldenTicketRaw();
        assertEq((g >> 189) & 1, 1, "armed");
        winner = uint32(g);

        h.setDailyIdx(ARM_IDX + 1);
        vm.recordLogs();
        h.runDailyJackpot(true, LVL, _word([1, 2, 3, 4], [1, 2, 3, 4], 0xBEEF), gasleft());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("GoldenTicketWin(uint32,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) found = true;
        }
        assertEq((h.goldenTicketRaw() >> 189) & 1, 0, "the arm is spent by the resolve");
    }

    function test_evenIdWinnerStillResolves() public {
        (bool found, uint32 winner) = _resolves(0x1001);
        assertEq(winner & 1, 0, "fixture: the armed winner ID is even");
        assertTrue(found, "an even-ID winner's ticket resolves on the next board");
    }

    function test_oddIdWinnerResolves() public {
        (bool found, uint32 winner) = _resolves(0x1000);
        assertEq(winner & 1, 1, "fixture: the armed winner ID is odd");
        assertTrue(found, "an odd-ID winner's ticket resolves on the next board");
    }
}
