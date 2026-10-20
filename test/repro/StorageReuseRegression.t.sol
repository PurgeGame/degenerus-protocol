// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract JackpotStorageReuseHarness is DegenerusGameStorage {
    function poison() external {
        assembly ("memory-safe") {
            sstore(jackpotWork.slot, not(0))
            sstore(add(jackpotWork.slot, 1), not(0))
        }
    }

    function start(uint256 budget, uint32 traits, uint24 lvl, uint8 kind, uint8 quadrant,
        bool finalDay, bool directTickets) external
    {
        _startJackpotWork(uint128(budget), traits, lvl, kind, quadrant, finalDay, directTickets);
    }

    function retire() external { _retireJackpotWork(); }
    function work() external view returns (JackpotWork memory) { return jackpotWork; }
}

contract JackpotStorageReuseTest is Test {
    JackpotStorageReuseHarness private harness;

    function setUp() public { harness = new JackpotStorageReuseHarness(); }

    function testFuzz_StartOverwritesEveryRetainedField(uint256 budget, uint32 traits, uint24 lvl,
        uint8 kind, uint8 quadrant, bool finalDay, bool directTickets) public
    {
        harness.poison();
        harness.start(budget, traits, lvl, kind, quadrant, finalDay, directTickets);
        DegenerusGameStorage.JackpotWork memory work = harness.work();
        assertEq(work.budget, uint128(budget));
        assertEq(work.paid, 0, "old paid must not survive initialization");
        assertEq(work.traits, traits);
        assertEq(work.lvl, lvl);
        assertEq(work.winner, 0);
        assertEq(work.kind, kind);
        assertEq(work.quadrant, quadrant);
        assertEq(work.finalDay, finalDay);
        assertEq(work.directTicketRound, 0);
        assertEq(work.directTickets, directTickets);

        harness.retire();
        work.kind = 0;
        assertEq(abi.encode(harness.work()), abi.encode(work), "retirement changes only kind");
        harness.start(1, 2, 3, 4, 5, !finalDay, !directTickets);
        work = harness.work();
        assertEq(work.budget, 1);
        assertEq(work.paid, 0);
        assertEq(work.traits, 2);
        assertEq(work.lvl, 3);
        assertEq(work.winner, 0);
        assertEq(work.kind, 4);
        assertEq(work.quadrant, 5);
        assertEq(work.finalDay, !finalDay);
        assertEq(work.directTicketRound, 0);
        assertEq(work.directTickets, !directTickets);
    }
}

contract RedemptionStorageReuseTest is RedemptionFixture {
    function _seedThreeClaims() private returns (uint32 batchId) {
        uint256 amount = sdgnrs.totalSupply() / 1000;
        _burn(alice, amount);
        _burn(bob, amount);
        _burn(carol, amount);
        batchId = _resolveLive(100);
    }

    function _assertNoTerminalClaim(address player, uint32 batchId) private {
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(player);
        sdgnrs.claimRedemption(0, batchId);
    }

    function test_PaidPrefixStaysConsumedWhenRemainderBecomesTerminal() public {
        uint32 batchId = _seedThreeClaims();
        assertFalse(_work(_oneClaimBudget()));
        assertEq(_cursor(), 1);
        assertEq(_claimTokens(alice, batchId), 0);
        assertGt(_claimTokens(bob, batchId), 0);
        uint256 credit = game.claimableWinningsOf(alice);
        _terminalize();
        _assertNoTerminalClaim(alice, batchId);
        // Manual terminal claims may arrive out of FIFO order.
        uint256 before = _received(carol);
        vm.prank(carol);
        sdgnrs.claimRedemption(0, batchId);
        assertGt(_received(carol), before);
        _assertNoTerminalClaim(carol, batchId);
        before = _received(bob);
        vm.prank(bob);
        sdgnrs.claimRedemption(0, batchId);
        assertGt(_received(bob), before);
        _assertNoTerminalClaim(bob, batchId);
        assertEq(game.claimableWinningsOf(alice), credit);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_DroppedPrefixStaysConsumedWhenRemainderBecomesTerminal() public {
        uint32 batchId = _seedThreeClaims();
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"12345678");
        assertFalse(_work(_oneClaimBudget()));
        assertEq(_cursor(), 1);
        assertEq(_claimTokens(alice, batchId), 0);
        vm.clearMockedCalls();
        _terminalize();
        _assertNoTerminalClaim(alice, batchId);
        assertGt(_claimTokens(bob, batchId), 0);
    }
}
