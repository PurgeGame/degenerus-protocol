// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title PermissionlessGiftAndApproval
/// @notice Covers the permissionless-settlement behaviors added in the permissionless work:
///         caller-funded gift placement (degenerette) and deposit (coinflip), the WWXRP gift
///         exclusion, the approved-operator path, claimBingo permissionless settlement, and the
///         claimAffiliateDgnrs array overload (batch isolation + blank-array-is-self). The
///         security property under test is NO DRAIN: a gift never debits a non-consenting target.
contract PermissionlessGiftAndApproval is DeployProtocol {
    // Storage slots (game) — mirror DegeneretteResolveRepeg.t.sol.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 38;
    uint256 private constant DEGENERETTE_BETS_SLOT = 37;

    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant CURRENCY_WWXRP = 3;

    uint128 private constant MIN_BET_FLIP = 200 ether;
    uint128 private constant BET_ETH = 0.01 ether;

    // Same selectors across the contracts that declare them.
    error NotApproved();
    error NotSlotOwner();

    address private player; // the bet/stake owner (the target)
    address private gifter; // an unrelated third party that funds gifts

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("gift_player");
        gifter = makeAddr("gift_gifter");
        vm.deal(player, 1000 ether);
        vm.deal(gifter, 1000 ether);
        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet reverts E() when lootboxRngIndex == 0; seed it to 1.
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
    }

    function _betNonce(address who) internal view returns (uint64) {
        return uint64(uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT))))));
    }

    function _betSlot(address who, uint64 betId) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(who, uint256(DEGENERETTE_BETS_SLOT)));
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(betId), inner))));
    }

    function _fundFlip(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    // ----- Degenerette gift placement -----

    /// @notice A FLIP gift debits the FUNDER, never the player, and the bet belongs to the player.
    function testFlipGiftDebitsFunderNotPlayer() public {
        _fundFlip(gifter, MIN_BET_FLIP);
        _fundFlip(player, 1000 ether); // the player's FLIP must remain untouched
        uint256 playerBefore = coin.balanceOf(player);
        uint256 gifterBefore = coin.balanceOf(gifter);
        uint64 nonceBefore = _betNonce(player);

        vm.prank(gifter); // gifter is NOT the player and NOT approved
        game.placeDegeneretteBet(player, CURRENCY_FLIP, MIN_BET_FLIP, 1, 0, 0);

        assertEq(coin.balanceOf(player), playerBefore, "no drain: player FLIP untouched");
        assertLt(coin.balanceOf(gifter), gifterBefore, "funder paid the bet");
        uint64 nonceAfter = _betNonce(player);
        assertEq(nonceAfter, nonceBefore + 1, "bet recorded under the player");
        assertGt(_betSlot(player, nonceAfter), 0, "the player owns the gifted bet");
    }

    /// @notice An ETH gift is funded by the caller's msg.value; the player's ETH is untouched.
    function testEthGiftFundedByCaller() public {
        uint256 playerEthBefore = player.balance;
        uint256 gifterEthBefore = gifter.balance;
        uint64 nonceBefore = _betNonce(player);

        vm.prank(gifter);
        game.placeDegeneretteBet{value: BET_ETH}(player, CURRENCY_ETH, BET_ETH, 1, 0, 0);

        assertEq(gifter.balance, gifterEthBefore - BET_ETH, "funder's ETH funded the bet");
        assertEq(player.balance, playerEthBefore, "no drain: player ETH untouched");
        assertEq(_betNonce(player), nonceBefore + 1, "bet recorded under the player");
    }

    /// @notice WWXRP bets cannot be gifted (player-or-approved only).
    function testWwxrpGiftReverts() public {
        vm.prank(gifter);
        vm.expectRevert(NotApproved.selector);
        game.placeDegeneretteBet(player, CURRENCY_WWXRP, 1 ether, 1, 0, 0);
    }

    /// @notice An approved operator spends the PLAYER's funds (the old funded-self path), not a gift.
    function testApprovedOperatorSpendsPlayerFunds() public {
        _fundFlip(player, MIN_BET_FLIP);
        vm.prank(player);
        game.setOperatorApproval(gifter, true);

        uint256 playerBefore = coin.balanceOf(player);
        uint256 gifterBefore = coin.balanceOf(gifter); // 0

        vm.prank(gifter);
        game.placeDegeneretteBet(player, CURRENCY_FLIP, MIN_BET_FLIP, 1, 0, 0);

        assertEq(coin.balanceOf(player), playerBefore - MIN_BET_FLIP, "approved op spends player's FLIP");
        assertEq(coin.balanceOf(gifter), gifterBefore, "approved operator is not charged");
    }

    // ----- Coinflip gift deposit -----

    /// @notice A coinflip deposit gift burns the FUNDER's FLIP, leaves the player's FLIP untouched,
    ///         and credits the stake to the player (the CoinflipDeposit event is keyed on player).
    function testCoinflipDepositGiftNoDrain() public {
        uint256 amt = 100 ether; // MIN
        _fundFlip(gifter, amt);
        _fundFlip(player, 500 ether);
        uint256 playerBefore = coin.balanceOf(player);
        uint256 gifterBefore = coin.balanceOf(gifter);

        vm.expectEmit(true, false, false, false, address(coinflip));
        emit CoinflipDeposit(player, 0); // assert topic1 (player) only; amount not checked

        vm.prank(gifter);
        coinflip.depositCoinflip(player, amt);

        assertEq(coin.balanceOf(player), playerBefore, "no drain: player FLIP untouched");
        assertEq(coin.balanceOf(gifter), gifterBefore - amt, "funder's FLIP funded the stake");
    }

    event CoinflipDeposit(address indexed player, uint256 creditedFlip);

    // ----- claimBingo permissionless -----

    /// @notice A non-approved third party may settle another player's bingo: there is no approval
    ///         gate, so the call falls through to the 8-color slot-ownership check.
    function testClaimBingoThirdPartyPassesGate() public {
        uint32[8] memory slots;
        vm.prank(gifter);
        vm.expectRevert(NotSlotOwner.selector);
        game.claimBingo(player, 1, 0, slots);
    }

    /// @notice Self-claim (address(0)) resolves to msg.sender (fails later on slot ownership).
    function testClaimBingoSelfPassesGate() public {
        uint32[8] memory slots;
        vm.prank(player);
        vm.expectRevert(NotSlotOwner.selector);
        game.claimBingo(address(0), 1, 0, slots);
    }

    /// @notice Operator approval is neither required nor harmful on the permissionless path.
    function testClaimBingoApprovedOperatorPassesGate() public {
        vm.prank(player);
        game.setOperatorApproval(gifter, true);
        uint32[8] memory slots;
        vm.prank(gifter);
        vm.expectRevert(NotSlotOwner.selector);
        game.claimBingo(player, 1, 0, slots);
    }

    // ----- claimAffiliateDgnrs array overload -----

    /// @notice The batch overload is per-item isolated: a list of ineligible affiliates does NOT
    ///         revert (each item's revert is swallowed), unlike the single-affiliate entry.
    function testAffiliateBatchIsolatesIneligible() public {
        address[] memory affs = new address[](2);
        affs[0] = player;
        affs[1] = gifter;
        vm.prank(gifter); // permissionless: any caller
        game.claimAffiliateDgnrs(affs); // must NOT revert
    }

    /// @notice A blank array claims the caller's own — so it propagates the (ineligible) revert.
    function testAffiliateBlankArrayIsSelf() public {
        address[] memory empty = new address[](0);
        vm.prank(player);
        vm.expectRevert();
        game.claimAffiliateDgnrs(empty);
    }
}
