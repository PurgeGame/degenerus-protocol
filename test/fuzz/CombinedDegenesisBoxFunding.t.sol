// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisDeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title CombinedDegenesisBoxFunding
/// @notice A Degenesis box is funded by whatever the buyer brings: a buyer holding no claimable
///         and no afking buys a ticket (earning the credit) and then a box paid entirely from
///         fresh ETH, and each purchase is its own order that consumes its own credit.
///         Assertions read the purchase event, the cohort header and balances.
contract CombinedDegenesisBoxFunding is DegenesisDeployProtocol {
    bytes32 constant DEGENESIS_BUY = keccak256("DegenesisBuy(uint32,uint8,uint32,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) game.mineFlip(0);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 777);
        for (uint256 i; i < 100; ++i) {
            (bool done,,) = game.dailySessionState();
            if (done) break;
            game.mineFlip(0);
        }
        assertEq(game.currentDayView(), 2, "first Degenesis sale cohort");
    }

    function _header(uint256 cohort) private view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(cohort, GameSlots.DEGENESIS_DAYS))));
    }

    /// @dev The one DegenesisBuy log of `logs` for `buyer`: (cohort day, order index, amount).
    function _buyEvent(Vm.Log[] memory logs, address buyer) private view returns (uint8 day, uint32 index, uint256 amount) {
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != DEGENESIS_BUY) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf_g3120(buyer), "the event names the buyer");
            (day, index, amount,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256));
            found = true;
        }
        assertTrue(found, "DegenesisBuy emitted");
    }

    /// @notice Fresh ETH alone funds both the ticket and the box: no claimable, no afking.
    function test_FreshEthFundsDegenesisBox_NoClaimable() public {
        address buyer = makeAddr("comboBuyer");
        uint256 mintCost = 0.24 ether; // 24 whole tickets at the level-1 price
        uint256 boxAmount = 0.05 ether;
        vm.deal(buyer, mintCost + boxAmount);

        vm.prank(buyer);
        game.purchase{value: mintCost}(0, 9600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.degenesisCreditOf(buyer), 0.06 ether, "the ticket earned a quarter as credit");

        uint256 poolBefore = game.claimablePoolView();
        vm.recordLogs();
        vm.prank(buyer);
        game.buyDegenesisBox{value: boxAmount}(0, boxAmount);

        (uint8 day, uint32 index, uint256 amount) = _buyEvent(vm.getRecordedLogs(), buyer);
        assertEq(day, 1, "the first sale day's cohort");
        assertEq(index, 0, "the first order of the cohort");
        assertEq(amount, boxAmount, "box funded at the requested amount");
        assertEq(buyer.balance, 0, "fresh ETH funded both the ticket and the box");
        assertEq(game.claimablePoolView() - poolBefore, boxAmount, "the box ETH is held in claimablePool until the split");
        assertEq(uint48(_header(1)), boxAmount / 1e14, "the cohort volume carries the order");
        assertEq(game.degenesisCreditOf(buyer), 0.01 ether, "the box consumed its amount in credit");
    }

    /// @notice A repeat purchase by the same wallet is its own order and consumes its own credit; one past
    ///         the credit reverts and keeps nothing.
    function test_RepeatPurchaseIsItsOwnOrder() public {
        address buyer = makeAddr("repeatBuyer");
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.purchase{value: 0.48 ether}(0, 19_200, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.degenesisCreditOf(buyer), 0.12 ether, "the purchase funds two box attempts");

        for (uint32 n; n < 2; ++n) {
            vm.recordLogs();
            vm.prank(buyer);
            game.buyDegenesisBox{value: 0.05 ether}(0, 0.05 ether);
            (, uint32 index, uint256 amount) = _buyEvent(vm.getRecordedLogs(), buyer);
            assertEq(index, n, "each purchase is the next order");
            assertEq(amount, 0.05 ether);
            assertEq(game.degenesisCreditOf(buyer), 0.12 ether - 0.05 ether * (uint256(n) + 1), "each purchase consumes its own credit");
        }
        assertEq(_header(1) >> 48 & type(uint32).max, 2, "two orders in the cohort");
        assertEq(uint48(_header(1)), 0.1 ether / 1e14, "the cohort volume is the sum");

        uint256 poolBefore = game.claimablePoolView();
        uint256 gameBalance = address(game).balance;
        uint256 buyerBalance = buyer.balance;
        uint256 header = _header(1);
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("E()")));
        game.buyDegenesisBox{value: 0.05 ether}(0, 0.05 ether);
        assertEq(game.degenesisCreditOf(buyer), 0.02 ether, "the failed buy rolls back the credit debit");
        assertEq(_header(1), header, "the failed buy appends nothing");
        assertEq(game.claimablePoolView(), poolBefore, "the failed buy holds nothing");
        assertEq(address(game).balance, gameBalance, "the failed buy retains no payment");
        assertEq(buyer.balance, buyerBalance, "the failed buy refunds its fresh ETH");
    }
}
