// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BurnieCoinflip} from "../../contracts/BurnieCoinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CoinflipCarryClaim — partial carry withdrawal while staying on auto-rebuy
/// @notice Proves claimCoinflipCarry:
///         1. PARTIAL  — settles resolved days first (win rolls into carry with the
///                       recycle bonus), withdraws exactly `amount` as minted BURNIE,
///                       and the remainder keeps riding the next flip.
///         2. CAP      — `amount` above the carry claims the whole carry and leaves
///                       auto-rebuy ENABLED (it is a withdrawal, not an exit).
///         3. ORDER    — a pending loss is settled BEFORE the withdrawal, so a wiped
///                       carry cannot be extracted around the loss.
///         4. GATES    — reverts RngLocked during the lock window and
///                       AutoRebuyNotEnabled for a player not on auto-rebuy.
///         5. TAKE-PROFIT — with autoRebuyStop = T, a win banks floor(payout/T)*T
///                       into claimableStored (claimCoinflips territory) and only
///                       the remainder plus its recycle bonus rolls as carry;
///                       claimCoinflipCarry pays from the carry alone.
contract CoinflipCarryClaim is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    address internal player;
    address internal operator;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("carry_player");
        operator = makeAddr("carry_operator");
        // Wall clock at day 2 so deposits target day 3 (clear of the day-1/2 seeds).
        _warpToDay(2);
    }

    /// @dev Wall clock just inside GameTimeLib day `d`.
    function _warpToDay(uint24 d) internal {
        vm.warp(
            (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
    }

    /// @dev Resolve day `epoch` as the GAME with a win or loss word, with the wall
    ///      clock at `epoch` (production timing: the bounty/leaderboard credit paths
    ///      inside the resolution target a FUTURE day, never the resolving one).
    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 word = uint256(keccak256(abi.encodePacked("carry_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }

    /// @dev Fund + enable rebuy (0 take-profit) + deposit a 100k stake for day 3.
    function _enterRebuyWithStake() internal returns (uint256 stake) {
        return _enterRebuyWithStake(0);
    }

    /// @dev Fund + enable rebuy with `takeProfit` + deposit a 100k stake for day 3.
    ///      The deposit is operator-routed (indirect) so it cannot set the
    ///      biggest-flip record or arm the bounty - keeps the carry math exact.
    function _enterRebuyWithStake(uint256 takeProfit) internal returns (uint256 stake) {
        stake = 100_000 ether;
        vm.prank(GAME);
        coin.mintForGame(player, stake);
        vm.prank(player);
        game.setOperatorApproval(operator, true);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), true, takeProfit);
        vm.prank(operator);
        coinflip.depositCoinflip(player, stake);
    }

    /// @dev Win payout for `stake` on day `epoch`, plus the capped recycle bonus the
    ///      roll applies to the carry.
    function _carryAfterWin(uint256 stake, uint24 epoch) internal view returns (uint256) {
        (uint16 r, ) = coinflip.getCoinflipDayResult(epoch);
        uint256 payout = stake + (stake * uint256(r)) / 100;
        uint256 bonus = (payout * 75) / 10_000;
        if (bonus > 1000 ether) bonus = 1000 ether;
        return payout + bonus;
    }

    function test_PartialClaimLeavesRemainderRolling() public {
        uint256 stake = _enterRebuyWithStake();
        _resolveDay(3, true);

        uint256 expectedCarry = _carryAfterWin(stake, 3);
        uint256 take = 50_000 ether;
        uint256 balBefore = coin.balanceOf(player);

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(address(0), take);

        assertEq(claimed, take, "claims exactly the requested amount");
        assertEq(coin.balanceOf(player) - balBefore, take, "claimed BURNIE minted to wallet");
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertTrue(enabled, "still on auto-rebuy");
        assertEq(carry, expectedCarry - take, "remainder stays as carry");
        assertEq(
            coinflip.previewClaimCoinflips(player),
            0,
            "0 take-profit: nothing banked to the claimable side"
        );

        // The remainder rides the next flip: a day-4 win compounds from the REDUCED carry.
        _resolveDay(4, true);
        uint256 expectedNext = _carryAfterWin(expectedCarry - take, 4);
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0); // settle-only probe (claims nothing)
        (, , uint256 carryNext, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryNext, expectedNext, "remainder kept rolling and compounded");
    }

    function test_FullClaimCapsAtCarryAndStaysOnRebuy() public {
        uint256 stake = _enterRebuyWithStake();
        _resolveDay(3, true);
        uint256 expectedCarry = _carryAfterWin(stake, 3);

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(address(0), type(uint256).max);

        assertEq(claimed, expectedCarry, "claim caps at the full carry");
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, 0, "carry drained");
        assertTrue(enabled, "withdrawal is not an exit - auto-rebuy stays on");
    }

    function test_PendingLossSettlesBeforeWithdrawal() public {
        uint256 stake = _enterRebuyWithStake();
        _resolveDay(3, true);
        _resolveDay(4, false); // the rolled carry dies on day 4, not yet walked for the player

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(address(0), type(uint256).max);

        assertEq(claimed, 0, "the loss is settled first - nothing to extract around it");
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, 0, "carry wiped by the settled loss");
        assertEq(coin.balanceOf(player), 0, "no BURNIE escaped the loss");
    }

    function test_TakeProfitBanksReservedChunksAndCarriesRemainder() public {
        // Not a 1000-ether multiple, so the payout (always one) can never split
        // evenly into chunks: both the reserved and remainder legs are exercised.
        uint256 takeProfit = 30_001 ether;
        uint256 stake = _enterRebuyWithStake(takeProfit);
        _resolveDay(3, true);

        (uint16 r, ) = coinflip.getCoinflipDayResult(3);
        uint256 payout = stake + (stake * uint256(r)) / 100;
        uint256 reserved = (payout / takeProfit) * takeProfit;
        uint256 remainder = payout - reserved;
        assertGt(reserved, 0, "fixture must bank at least one chunk");
        assertGt(remainder, 0, "fixture must leave a rolling remainder");
        uint256 bonus = (remainder * 75) / 10_000;
        if (bonus > 1000 ether) bonus = 1000 ether;
        uint256 expectedCarry = remainder + bonus;

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(address(0), type(uint256).max);

        assertEq(
            claimed,
            expectedCarry,
            "carry claim pays the remainder + its recycle bonus, never the reserved chunks"
        );
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertTrue(enabled, "still on auto-rebuy");
        assertEq(carry, 0, "carry drained");
        assertEq(
            coinflip.previewClaimCoinflips(player),
            reserved,
            "reserved chunks banked to the claimable side"
        );
        assertEq(
            coin.balanceOf(player),
            expectedCarry,
            "only the carry was minted by the carry claim"
        );

        // The banked side pays out through claimCoinflips, not the carry path.
        vm.prank(player);
        uint256 storedClaimed = coinflip.claimCoinflips(address(0), type(uint256).max);
        assertEq(storedClaimed, reserved, "banked take-profit claims via claimCoinflips");
        assertEq(
            coin.balanceOf(player),
            expectedCarry + reserved,
            "wallet ends with carry + banked chunks"
        );
    }

    function test_RevertsDuringRngLock() public {
        _enterRebuyWithStake();
        _resolveDay(3, true);

        vm.mockCall(
            GAME,
            abi.encodeWithSelector(IDegenerusGame.rngLocked.selector),
            abi.encode(true)
        );
        vm.prank(player);
        vm.expectRevert(BurnieCoinflip.RngLocked.selector);
        coinflip.claimCoinflipCarry(address(0), 1 ether);
        vm.clearMockedCalls();
    }

    function test_RevertsWithoutAutoRebuy() public {
        vm.prank(player);
        vm.expectRevert(BurnieCoinflip.AutoRebuyNotEnabled.selector);
        coinflip.claimCoinflipCarry(address(0), 1 ether);
    }
}
