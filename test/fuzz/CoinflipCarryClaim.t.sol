// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CoinflipCarryClaim — partial carry withdrawal while staying on auto-rebuy
/// @notice Proves claimCoinflipCarry:
///         1. PARTIAL  — settles resolved days first (win rolls into carry with the
///                       recycle bonus), withdraws exactly `amount` as minted FLIP,
///                       and the remainder keeps riding the next flip.
///         2. CAP      — `amount` above the carry claims the whole carry and leaves
///                       auto-rebuy ENABLED (it is a withdrawal, not an exit).
///         3. ORDER    — a pending loss is settled BEFORE the withdrawal, so a wiped
///                       carry cannot be extracted around the loss.
///         4. GATES    — reverts RngLocked until today's flip is APPLIED (reopening at
///                       settlement, even with the game's RNG lock still up), and
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
        // Day 2 APPLIED, wall clock still on it: the carry gates open only once the day's
        // word has been processed, and deposits from here target day 3 (clear of the
        // day-1/2 seeds). The player holds nothing on day 2, so the resolve is inert for it.
        _resolveDay(2, false);
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
        assertEq(coin.balanceOf(player) - balBefore, take, "claimed FLIP minted to wallet");
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
        assertEq(coin.balanceOf(player), 0, "no FLIP escaped the loss");
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

    /// Day 4 is unapplied while the carry rides it: the claim is shut, lock or no lock.
    function test_RevertsWhileTodaysFlipUnresolved() public {
        _enterRebuyWithStake();
        _resolveDay(3, true);
        _warpToDay(4);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.claimCoinflipCarry(address(0), 1 ether);
    }

    /// The other side: day 3's payouts are applied and the lock is STILL held (advanceGame
    /// defers the unlock behind its chunked drains). The carry has resolved through day 3's
    /// word and rides day 4, unrequested, so the withdrawal behaves as it would post-unlock.
    /// The mocked lock is the point: it must not gate this path.
    function test_OpensOnceTodaysFlipResolvedUnderHeldLock() public {
        _enterRebuyWithStake();
        _resolveDay(3, true);

        _lockRng();
        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(address(0), 1 ether);
        vm.clearMockedCalls();

        assertEq(claimed, 1 ether, "settled carry withdraws under a still-held lock");
        assertEq(coin.balanceOf(player), 1 ether, "and mints to the player");
    }

    function _lockRng() internal {
        vm.mockCall(
            GAME,
            abi.encodeWithSelector(IDegenerusGame.rngLocked.selector),
            abi.encode(true)
        );
    }

    // ---------------------------------------------------------------------
    // 6. The carry is unreachable from FLIP's burn-shortfall leg
    // ---------------------------------------------------------------------

    /// FLIP's `_consumeCoinflipShortfall` carries NO freeze gate, on the claim that
    /// `consumeCoinflipsForBurn` reaches `claimableStored` only — settled days the pending word
    /// cannot reprice. That claim rests on an adjacency inside `_setCoinflipAutoRebuy`: the sole
    /// writer of `autoRebuyEnabled = false` drains the carry in the same block, so the
    /// `else if (oldCarry != 0)` branch in `_claimCoinflipsInternal` (which WOULD fold a carry
    /// into `mintable`) is unreachable. Pin it here rather than leave it to inspection: the
    /// position is frozen, a live carry rides the unapplied day, and a consume for an arbitrary
    /// amount must take the settled bank and leave the carry exactly as it found it.
    function testFuzz_BurnConsumeNeverReachesTheCarry(uint96 wantRaw) public {
        _enterRebuyWithStake(50_000 ether); // take-profit banks chunks AND leaves a carry
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0); // settle while day 3 is applied
        _warpToDay(4); // day 4 unapplied: the position is frozen and the carry rides it

        (, , uint256 carryBefore, ) = coinflip.coinflipAutoRebuyInfo(player);
        uint256 bankBefore = coinflip.previewClaimCoinflips(player);
        assertGt(carryBefore, 0, "precondition: a carry is riding the unapplied day");
        assertGt(bankBefore, 0, "precondition: a settled bank exists to draw from");

        vm.prank(ContractAddresses.COIN);
        uint256 consumed = coinflip.consumeCoinflipsForBurn(player, uint256(wantRaw) + 1);

        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryAfter, carryBefore, "consume must never reduce the auto-rebuy carry");
        assertLe(consumed, bankBefore, "consume is capped by the settled bank");
    }

    /// The adjacency itself: an exit can never leave a carry stranded behind a disabled flag.
    function test_DisabledPositionNeverHoldsACarry() public {
        _enterRebuyWithStake();
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertGt(carry, 0, "precondition: a carry exists to strand");

        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        (bool enabled, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertFalse(enabled, "position is disabled");
        assertEq(carryAfter, 0, "and holds no carry the burn path could later fold into mintable");
    }

    /// THE requirement, stated whole: nobody can change the carry amount riding the current
    /// day's flip after that day's result becomes knowable. `autoRebuyCarry` has six writers;
    /// five are externally reachable. This drives every one of them while day 4 sits unapplied
    /// with a live carry on it, and asserts the carry is byte-identical at the end.
    ///
    ///   consumeFlipForSalvage      -> only via FLIP.burnCoinForSalvage, frozen-gated (below)
    ///   _setCoinflipAutoRebuy      -> the exit and the re-arm, both revert here
    ///   claimCoinflipCarry         -> reverts here
    ///   withdrawRedeemedFlip       -> sDGNRS-only, gated at sDGNRS.burn by the RNG lock AND by
    ///                                 its own rngWordForDay(today) != 0 submit check
    ///   _claimCoinflipsInternal    -> ungated, but its walk stops at flipsClaimableDay, which
    ///                                 by definition of the freeze is strictly before day 4 —
    ///                                 so it can only ever fold ALREADY-public resolved days,
    ///                                 and `lastClaim` makes that idempotent. Driven below.
    function test_NoReachablePathMovesTheCarryRidingAnUnappliedDay() public {
        _enterRebuyWithStake(50_000 ether);
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0); // settle while day 3 is applied
        _warpToDay(4); // day 4 unapplied: its word may be public, the carry rides it

        (, , uint256 carry0, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertGt(carry0, 0, "precondition: a carry is riding the unapplied day");

        // --- gated mutators: every one shut ---
        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), true, 1 ether);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(address(0), 1 ether);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.claimCoinflipCarry(address(0), type(uint256).max);

        vm.prank(ContractAddresses.GAME);
        vm.expectRevert(FLIP.Insufficient.selector);
        coin.burnCoinForSalvage(player, 1 ether);

        // --- ungated settle paths: open, and provably carry-neutral ---
        vm.prank(player);
        coinflip.claimCoinflips(address(0), type(uint256).max);
        vm.prank(ContractAddresses.COIN);
        coinflip.consumeCoinflipsForBurn(player, type(uint256).max);
        vm.prank(ContractAddresses.COIN);
        coinflip.claimCoinflipsFromFlip(player, type(uint256).max);

        // --- a fresh deposit rides TOMORROW, never the unapplied day ---
        vm.prank(GAME);
        coin.mintForGame(player, 10_000 ether);
        vm.prank(player);
        coinflip.depositCoinflip(address(0), 10_000 ether);

        (, , uint256 carry1, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry1, carry0, "no reachable path moved the carry riding the unapplied day");
    }

    function test_RevertsWithoutAutoRebuy() public {
        vm.prank(player);
        vm.expectRevert(Coinflip.AutoRebuyNotEnabled.selector);
        coinflip.claimCoinflipCarry(address(0), 1 ether);
    }
}
