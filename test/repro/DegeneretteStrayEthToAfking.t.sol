// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @notice Regression: ETH sent alongside a FLIP Degenerette bet — which consumes no
///         ETH — is credited to the funder's withdrawable afking balance (solvency-preserving via
///         claimablePool), not stranded in the contract. A zero-value token bet is unaffected.
contract DegeneretteStrayEthToAfking is DeployProtocol {
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;
    uint32 private constant TICKET = 0x01020304;

    address private player;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        player = makeAddr("stray_eth_player");
        vm.deal(player, 1_000 ether);
        vm.deal(address(game), 1_000_000 ether);
        // LR index = 1 so placement passes NotStarted; the word stays 0 (placement needs it unfulfilled).
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
        _seedFuturePrizePool(10_000_000 ether);
    }

    function test_flip_bet_strayEth_creditsAfking() public {
        uint128 perTicket = 100 ether;
        vm.prank(address(game));
        coin.mintForGame(player, perTicket);

        uint256 afkingBefore = game.afkingFundingOf(player);
        uint256 poolBefore = game.claimablePoolView();
        uint256 stray = 5 ether;

        vm.prank(player);
        game.placeDegeneretteBet{value: stray}(address(0), CURRENCY_FLIP, perTicket, 1, uint8(TICKET & 7));

        assertEq(game.afkingFundingOf(player), afkingBefore + stray, "stray ETH not credited to afking");
        assertEq(
            game.claimablePoolView(),
            poolBefore + stray,
            "claimablePool must rise by the credited afking (solvency identity preserved)"
        );
    }

    /// @notice Rejected WWXRP placement cannot trap ETH or create afking credit.
    function test_wwxrp_bet_strayEth_revertsAtomically() public {
        vm.prank(address(game));
        wwxrp.mintPrize(player, 1 ether);
        uint256 afkingBefore = game.afkingFundingOf(player);
        uint256 poolBefore = game.claimablePoolView();
        uint256 ethBefore = player.balance;
        uint256 gameBefore = address(game).balance;
        vm.expectRevert(bytes4(keccak256("UnsupportedCurrency()")));
        vm.prank(player);
        game.placeDegeneretteBet{value: 3 ether}(address(0), CURRENCY_WWXRP, 1 ether, 1, uint8(TICKET & 7));
        assertEq(player.balance, ethBefore, "rejected bet retained the payment");
        assertEq(address(game).balance, gameBefore, "rejected bet funded the game");
        assertEq(wwxrp.balanceOf(player), 1 ether, "rejected bet burned WWXRP");
        assertEq(game.afkingFundingOf(player), afkingBefore, "rejected bet credited afking");
        assertEq(game.claimablePoolView(), poolBefore, "rejected bet changed claimable pool");
    }

    function test_flip_bet_noEth_afkingUnchanged() public {
        uint128 perTicket = 100 ether;
        vm.prank(address(game));
        coin.mintForGame(player, perTicket);

        uint256 afkingBefore = game.afkingFundingOf(player);
        uint256 poolBefore = game.claimablePoolView();

        vm.prank(player);
        game.placeDegeneretteBet(address(0), CURRENCY_FLIP, perTicket, 1, uint8(TICKET & 7));

        assertEq(game.afkingFundingOf(player), afkingBefore, "no-ETH token bet must not touch afking");
        assertEq(game.claimablePoolView(), poolBefore, "no-ETH token bet must not touch claimablePool");
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 newPacked = (currentPacked & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }
}
