// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {TerminalLoanBase} from "./TerminalLoanSettlement.t.sol";

/// @title RngVectorTerminalLoans -- the terminal word is requested only after every loan has
///        settled, and nothing about any loan moves while it is out
/// @notice A VRF-alive game over with a mixed book (a borrower who repays at the current price, a
///         defaulter, a smurf's loan). The ending is mined one call at a time. At the call that
///         sends the terminal request every loan is already settled and the settlement cursor is
///         clear. While the word is out every loan record, borrower balance and account owner
///         stays byte-identical and the borrow and repay doors stay shut; through the payout the
///         loan records and owners stay as they were at the request.
contract RngVectorTerminalLoans is TerminalLoanBase {
    address private alice = makeAddr("rv-loan-alice");
    address private bob = makeAddr("rv-loan-bob");
    address private carol = makeAddr("rv-loan-carol");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(address(game), 100_000 ether);
        gameRuntime = address(game).code;
        lens = new DegenerusGameLens();
        _seeder().livePurchase(5);
        _restore();
        _fund(SDGNRS_ID, 5_000 ether);
    }

    function _account(address who) private returns (uint32 id) {
        vm.deal(who, 1_000 ether);
        id = _giveWalletId(who);
        _seedLevel(id, 60, 4_000);
        _seedLevel(id, 102, 4_000);
    }

    /// @dev The tracked loans' records and account owners, plus (with `balances`) the borrowers'
    ///      claimable and AFKing balances.
    function _loanDigest(bool balances) private view returns (bytes32 h) {
        for (uint256 i; i < tracked.length; ++i) {
            uint32 id = tracked[i];
            DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
            h = keccak256(abi.encode(h, id, info.principal, info.dueLevel, _payee(id), game.acquiredBuyer(id)));
            if (balances) {
                (uint128 claimable, uint128 afking) = lens.accountBalances(address(game), id);
                h = keccak256(abi.encode(h, claimable, afking));
            }
        }
    }

    function _lootboxRngWord() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(GameSlots.LOOTBOX_RNG_PACKED))));
    }

    function test_TerminalRequestFollowsEverySettlementAndFreezesLoans() public {
        uint32 a = _account(alice);
        _borrow(alice, a, 10);
        uint256 owedA = _owedNow(a);
        _setBalances(a, owedA + 1, 0); // claimable keeps its 1-wei sentinel
        uint32 b = _account(bob);
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, bob, 1e15);
        _borrow(bob, b, 3);
        _setBalances(b, 0, 0);
        uint32 c = _account(carol);
        _borrow(carol, c, 40);
        _setBalances(c, 1, 0);

        _seeder().pastDeadline();
        _restore();
        assertTrue(game.livenessTriggered(), "the ending fires with VRF alive");
        requestAtDecision = mockVRF.lastRequestId();

        uint256 calls;
        for (; calls < 200 && mockVRF.lastRequestId() == requestAtDecision; ++calls) {
            _mine(30_000_000);
        }
        assertEq(mockVRF.lastRequestId(), requestAtDecision + 1, "terminal request sent");
        assertFalse(_anyOpen(), "every loan settled before the terminal request");
        assertEq(_loanStep(), 0, "settlement cursor clear at the request");
        assertGt(calls, 2, "settlement had calls of its own ahead of the request");
        bytes32 digest = _loanDigest(true);
        bytes32 records = _loanDigest(false);

        // Inside the terminal window: the borrow and repay doors are shut and nothing moves.
        vm.prank(alice);
        vm.expectRevert();
        game.borrow(a, 20, type(uint256).max, 0);
        vm.prank(carol);
        vm.expectRevert();
        game.repay{value: 1 ether}(c);
        for (uint256 i; i < 3; ++i) _mine(30_000_000);
        assertEq(_loanDigest(true), digest, "loans and balances frozen while the terminal word is out");

        _driveEnding(30_000_000, true, 200);
        assertTrue(game.gameOver(), "ending finished");
        assertEq((_lootboxRngWord() >> 232) & 0xFF, 0, "the normal ending never latched the dead ending (LR_GO_DEAD)");
        assertEq(_loanDigest(false), records, "loan records and owners unchanged through the terminal payout");
        assertEq(_payee(b), address(sdgnrs), "bob defaulted before the request");
        assertEq(_payee(a), alice, "alice repaid before the request");
    }
}
