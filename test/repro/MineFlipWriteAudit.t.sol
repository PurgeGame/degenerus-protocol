// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Audit-only reference that also clears the board words. All inserts and winner reads use
///      production code.
contract BafRetainedPayloadAudit is DegenerusJackpots {
    function finalizeClearingPayload(uint24 lvl) external onlyGame {
        BafLevel memory current = bafLevel[lvl];
        if (current.topLen != 0) delete bafTop[(lvl / 10) & 3][0];
        if (current.topLen > 2) delete bafTop[(lvl / 10) & 3][1];
        unchecked {
            bafLevel[lvl] = BafLevel({epoch: current.epoch + 1, topLen: 0, skipped: false});
        }
    }

    function visibleBoard(uint24 lvl) external view returns (uint128[4] memory entries, uint8 len) {
        len = bafLevel[lvl].topLen;
        for (uint256 i; i < len; ++i) entries[i] = uint128(bafTop[(lvl / 10) & 3][i >> 1] >> ((i & 1) * 128));
    }

    function payload(uint24 lvl) external view returns (uint256, uint256) {
        return (bafTop[(lvl / 10) & 3][0], bafTop[(lvl / 10) & 3][1]);
    }
}

/// @notice Production finalizeBaf retains the board words; compare it against a reference that
///         clears them, through many epochs.
contract MineFlipWriteAuditTest is Test {
    BafRetainedPayloadAudit private cleared;
    BafRetainedPayloadAudit private retained;

    function setUp() public {
        cleared = new BafRetainedPayloadAudit();
        retained = new BafRetainedPayloadAudit();
        // Seed in setUp so the measured calls see original nonzero storage, not dirty slots.
        for (uint32 i = 2; i < 6; ++i) _creditBoth(i, 10, i * 100);
    }

    function _creditBoth(uint32 id, uint24 lvl, uint256 amount) private {
        vm.prank(ContractAddresses.COINFLIP);
        cleared.recordBafFlip(id, lvl, amount);
        vm.prank(ContractAddresses.COINFLIP);
        retained.recordBafFlip(id, lvl, amount);
    }

    function _finishBoth(uint24 lvl) private {
        vm.prank(ContractAddresses.GAME);
        cleared.finalizeClearingPayload(lvl);
        vm.prank(ContractAddresses.GAME);
        retained.finalizeBaf(lvl);
    }

    function _compare(uint24 lvl, uint256 word) private view {
        (uint128[4] memory a, uint8 an) = cleared.visibleBoard(lvl);
        (uint128[4] memory b, uint8 bn) = retained.visibleBoard(lvl);
        assertEq(an, bn, "visible board length");
        for (uint256 i; i < 4; ++i) assertEq(a[i], b[i], "visible lane");
        assertEq(cleared.bafHeadWinner(lvl, word, 0), retained.bafHeadWinner(lvl, word, 0), "top winner");
        assertEq(cleared.bafHeadWinner(lvl, word, 2), retained.bafHeadWinner(lvl, word, 2), "third/fourth winner");
    }

    function testFuzz_RetainedBoardMatchesClearedBoardAcrossEpochs(uint256 seed) public {
        for (uint256 epoch; epoch < 5; ++epoch) {
            _finishBoth(10);
            _finishBoth(20);
            _compare(10, seed);
            _compare(20, seed);
            for (uint256 i; i < 20; ++i) {
                uint256 r = uint256(keccak256(abi.encode(seed, epoch, i)));
                uint24 lvl = r & 1 == 0 ? 10 : 20;
                uint32 id = uint32(1 + ((r >> 8) % 10)); // Includes the excluded vault.
                uint256 amount = i % 7 == 0 ? 0 : (i % 11 == 0 ? type(uint128).max : (r >> 64) % 1000);
                _creditBoth(id, lvl, amount);
                _compare(lvl, r);
            }
        }
    }

    function test_RetainedBoardIsInvisibleUntilEachLaneIsOverwritten() public {
        (uint256 before0, uint256 before1) = retained.payload(10);
        assertGt(before0, 0);
        assertGt(before1, 0);
        _finishBoth(10);
        (uint256 after0, uint256 after1) = retained.payload(10);
        assertEq(after0, before0);
        assertEq(after1, before1);
        _compare(10, 123);
        // Fill one lane at a time with smaller scores: stale high scores must never win.
        for (uint32 id = 8; id < 12; ++id) {
            _creditBoth(id, 10, 1);
            _compare(10, uint256(id));
        }
    }

    function test_Gas_FinalizeFullBoard() public {
        vm.cool(address(cleared));
        vm.prank(ContractAddresses.GAME);
        cleared.finalizeClearingPayload(10);
        Vm.Gas memory baseline = vm.lastCallGas();
        vm.cool(address(retained));
        vm.prank(ContractAddresses.GAME);
        retained.finalizeBaf(10);
        Vm.Gas memory candidate = vm.lastCallGas();
        emit log_named_uint("clear: gross execution gas", baseline.gasTotalUsed);
        emit log_named_int("clear: refund counter", baseline.gasRefunded);
        emit log_named_uint("retain: gross execution gas", candidate.gasTotalUsed);
        emit log_named_int("retain: refund counter", candidate.gasRefunded);
        assertLt(candidate.gasTotalUsed, baseline.gasTotalUsed);
        _compare(10, 123);
    }
}
