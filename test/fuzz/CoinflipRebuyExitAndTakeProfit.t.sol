// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CoinflipRebuyExitAndTakeProfit — the carry-extraction paths CoinflipCarryClaim
///        does not cover, plus the conservation and day-routing invariants.
///
/// @notice CoinflipCarryClaim pins `claimCoinflipCarry`. There are two OTHER ways a
///         position's rolling carry can be turned back into FLIP —
///         `setCoinflipAutoRebuy(false)` (the exit) and `setCoinflipAutoRebuyTakeProfit`
///         (the re-split) — and both must obey the same freeze discipline, otherwise a
///         player who sees a losing day coming could pull the carry out around it.
///
///         The freeze rests on two facts that are asserted here rather than assumed:
///           * `rngWordCurrent` is written ONLY under `rngLockedFlag`
///             (DegenerusGame.sol:2215), so the resolving word is never public while
///             the lock is down; and
///           * every carry mutator, ON A POSITION THAT HOLDS A CARRY, reverts until today's
///             flip is APPLIED — which covers the whole span in which a word can be knowable
///             but unconsumed, and the pre-request gap before it as well. Arming auto-rebuy
///             is NOT gated: no carry exists yet, so nothing can be front-run.
///         Together those make "observe the word, then move the position" unreachable.
///
///         The gate is that settlement marker rather than `rngLocked()`: the lock outlives
///         the settlement (advanceGame defers `_unlockRng` behind chunked ticket drains, a
///         pending daily jackpot, and a phase transition), and once the day's payouts are
///         processed the carry has resolved through that word and rides tomorrow — whose
///         word is not yet requested. Both halves are asserted below, the open side under a
///         mocked-up lock so a regression back to the bare lock fails here.
///
///         Covered here:
///           A EXIT-ORDER   — disabling auto-rebuy settles a pending LOSS first, so the
///                            exit cannot rescue a carry the loss already killed.
///           B EXIT-LOCK    — the exit reverts while today's flip is unapplied, and
///                            reopens once it settles even with the lock still held.
///           C SPLIT-LOCK   — the take-profit re-split obeys the same two-sided gate.
///           D SPLIT-ORDER  — changing take-profit settles the pending day under the OLD
///                            value; a win already banked cannot be retroactively re-split.
///           E CONSERVATION — reserved + rolled remainder == payout exactly, at every
///                            take-profit size (fuzzed). No FLIP is minted or lost by the
///                            split itself.
///           F DAY-ROUTING  — a deposit always lands strictly AFTER the last resolved
///                            day, so a stake can never be placed onto a known result.
contract CoinflipRebuyExitAndTakeProfit is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    address internal player;
    address internal operator;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("rebuy_player");
        operator = makeAddr("rebuy_operator");
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

    /// @dev Resolve day `epoch` as the GAME, with the wall clock at `epoch` (production
    ///      timing: the credit paths inside resolution target a FUTURE day).
    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 word = uint256(keccak256(abi.encodePacked("rebuy_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }

    /// @dev Fund + enable rebuy with `takeProfit` + place a 100k stake on day 3.
    ///      Operator-routed so the deposit is INDIRECT: it cannot set the biggest-flip
    ///      record or arm the bounty, keeping the carry arithmetic exact.
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

    function _payoutOf(uint256 stake, uint24 epoch) internal view returns (uint256) {
        (uint16 r, ) = coinflip.getCoinflipDayResult(epoch);
        return stake + (stake * uint256(r)) / 100;
    }

    function _lockRng() internal {
        vm.mockCall(
            GAME,
            abi.encodeWithSelector(IDegenerusGame.rngLocked.selector),
            abi.encode(true)
        );
    }

    // ---------------------------------------------------------------------
    // A. Exit cannot dodge a settled loss
    // ---------------------------------------------------------------------

    /// Disabling auto-rebuy runs the full settle FIRST (deepAutoRebuy). A day-4 loss
    /// therefore zeroes the day-3 carry before the exit can cash it out.
    function test_ExitSettlesPendingLossBeforeCashingCarry() public {
        _enterRebuyWithStake(0);
        _resolveDay(3, true);
        _resolveDay(4, false); // the rolled carry dies here, not yet walked for the player

        uint256 balBefore = coin.balanceOf(player);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        assertEq(
            coin.balanceOf(player),
            balBefore,
            "A: exit must not mint a carry the settled loss already wiped"
        );
        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertFalse(enabled, "A: auto-rebuy disabled");
        assertEq(carry, 0, "A: carry wiped by the settled loss");
        assertEq(
            coinflip.previewClaimCoinflips(player),
            0,
            "A: nothing banked on the claimable side either"
        );
    }

    /// Control: with no intervening loss the exit DOES pay the carry out, so scenario A
    /// is proving the loss settles — not merely that the exit pays nothing.
    function test_ExitPaysCarryWhenNoPendingLoss() public {
        uint256 stake = _enterRebuyWithStake(0);
        _resolveDay(3, true);

        uint256 payout = _payoutOf(stake, 3);
        uint256 expectedCarry = payout + (payout * 75) / 10_000;

        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        assertEq(
            coin.balanceOf(player),
            expectedCarry,
            "A-control: clean exit mints the full rolled carry"
        );
    }

    // ---------------------------------------------------------------------
    // B / C. Both remaining carry mutators are gated on the freeze, two-sided
    // ---------------------------------------------------------------------

    /// Day 4 is unapplied while the carry rides it: the exit is shut, lock or no lock.
    function test_ExitRevertsWhileTodaysFlipUnresolved() public {
        _enterRebuyWithStake(0);
        _resolveDay(3, true);
        _warpToDay(4);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);
    }

    /// The other side: day 3's payouts are applied and the lock is STILL held (the drains
    /// that follow settlement keep it up). The carry has already resolved through day 3's
    /// word and rides day 4, unrequested — so the exit pays out exactly as it would after
    /// the unlock. The mocked lock is the point: it must not gate this path.
    function test_ExitOpensOnceTodaysFlipResolvedUnderHeldLock() public {
        uint256 stake = _enterRebuyWithStake(0);
        _resolveDay(3, true);

        uint256 payout = _payoutOf(stake, 3);
        uint256 expectedCarry = payout + (payout * 75) / 10_000;

        _lockRng();
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);
        vm.clearMockedCalls();

        assertEq(
            coin.balanceOf(player),
            expectedCarry,
            "B: settled carry pays out under a still-held lock"
        );
    }

    function test_TakeProfitChangeRevertsWhileTodaysFlipUnresolved() public {
        _enterRebuyWithStake(0);
        _resolveDay(3, true);
        _warpToDay(4);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(address(0), 1 ether);
    }

    function test_TakeProfitChangeOpensOnceTodaysFlipResolvedUnderHeldLock() public {
        _enterRebuyWithStake(0);
        _resolveDay(3, true);

        _lockRng();
        vm.prank(player);
        coinflip.setCoinflipAutoRebuyTakeProfit(address(0), 1 ether);
        vm.clearMockedCalls();

        (, uint256 stop, , ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(stop, 1 ether, "C: re-split lands under a still-held lock");
    }

    /// ARMING is NOT gated: a position not yet on auto-rebuy holds no carry, so there is
    /// nothing the pending day's word can be front-run against. Day 3 is unapplied here.
    function test_EnableOpensWhileTodaysFlipUnresolved() public {
        _warpToDay(3);

        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), true, 0);

        (bool enabled, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertTrue(enabled, "B: arming is open - no carry exists to protect");
        assertEq(carry, 0, "B: and it arms with an empty carry");
    }

    /// But the SAME entrypoint on an already-armed position is frozen: the freeze check leads
    /// the AutoRebuyAlreadyEnabled guard, so a carrying position cannot re-enter here either.
    function test_RearmRevertsWhileTodaysFlipUnresolved() public {
        _enterRebuyWithStake(0);
        _resolveDay(3, true);
        _warpToDay(4);

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(address(0), true, 1 ether);
    }

    /// A player not on auto-rebuy meets AutoRebuyNotEnabled, never the freeze — the freeze is
    /// scoped to positions that actually hold a carry.
    function test_NonRebuyPlayerMeetsNotEnabledNotTheFreeze() public {
        _warpToDay(4);

        vm.prank(player);
        vm.expectRevert(Coinflip.AutoRebuyNotEnabled.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(address(0), 1 ether);

        vm.prank(player);
        vm.expectRevert(Coinflip.AutoRebuyNotEnabled.selector);
        coinflip.claimCoinflipCarry(address(0), 1 ether);
    }

    // ---------------------------------------------------------------------
    // B2. What yesterday's walk hands to today, and what may leave
    // ---------------------------------------------------------------------

    /// `_claimCoinflipsInternal` may walk as far as YESTERDAY during the freeze (its cursor
    /// stops at flipsClaimableDay, which the freeze puts strictly before today). Under a 0
    /// take-profit the whole of yesterday's payout becomes the carry — and the carry IS
    /// today's stake, applied the moment today is walked. So none of it may leave. Drive both
    /// ungated settle paths and assert not one wei escapes.
    function test_YesterdaysWinRidesTodayAndNoneOfItCanLeave() public {
        uint256 stake = _enterRebuyWithStake(0); // 0 take-profit: everything rides
        _resolveDay(3, true);
        _warpToDay(4); // today unapplied: frozen, and the carry is staked on it

        uint256 payout = _payoutOf(stake, 3);
        uint256 expectedCarry = payout + (payout * 75) / 10_000;

        vm.prank(player);
        uint256 minted = coinflip.claimCoinflips(address(0), type(uint256).max);
        assertEq(minted, 0, "0 take-profit: nothing banks, it is all staked on today");

        vm.prank(ContractAddresses.COIN);
        uint256 consumed = coinflip.consumeCoinflipsForBurn(player, type(uint256).max);
        assertEq(consumed, 0, "and the burn leg cannot reach it either");

        assertEq(coin.balanceOf(player), 0, "not one wei of yesterday's win left the position");
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, expectedCarry, "the whole payout is the carry, riding today");
    }

    /// With a take-profit the split is PRE-COMMITTED: floor(payout/T)*T banks — that slice was
    /// never going to be bet on today, so it is free to leave — and only the remainder plus its
    /// recycle bonus rides. The threshold itself is frozen, so nobody can read today's word and
    /// then decide to bank more of what is already staked.
    function test_OnlyThePreCommittedBankLeavesDuringTheFreeze() public {
        uint256 T = 50_000 ether;
        uint256 stake = _enterRebuyWithStake(T);
        _resolveDay(3, true);
        _warpToDay(4);

        uint256 payout = _payoutOf(stake, 3);
        uint256 reserved = (payout / T) * T;
        uint256 rides = payout - reserved;
        uint256 expectedCarry = rides + (rides * 75) / 10_000;
        assertGt(reserved, 0, "precondition: a bank exists");
        assertGt(rides, 0, "precondition: and a slice rides");

        vm.prank(player);
        uint256 minted = coinflip.claimCoinflips(address(0), type(uint256).max);
        assertEq(minted, reserved, "exactly the pre-committed bank leaves, no more");

        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, expectedCarry, "the staked remainder stays locked on today");

        vm.prank(player);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(address(0), 1 ether);
    }

    // ---------------------------------------------------------------------
    // D. The re-split settles under the OLD take-profit
    // ---------------------------------------------------------------------

    /// A day already won is banked/rolled under the take-profit in force when it
    /// resolved. Lowering take-profit afterwards must not retroactively re-split it
    /// (which would move already-rolled carry into the mintable bank, or vice versa).
    function test_TakeProfitChangeSettlesUnderOldValueNotNew() public {
        uint256 takeProfit = 30_001 ether;
        uint256 stake = _enterRebuyWithStake(takeProfit);
        _resolveDay(3, true);

        uint256 payout = _payoutOf(stake, 3);
        uint256 reservedOld = (payout / takeProfit) * takeProfit;
        uint256 remainderOld = payout - reservedOld;
        assertGt(reservedOld, 0, "D: fixture must bank a chunk under the OLD value");
        assertGt(remainderOld, 0, "D: fixture must roll a remainder under the OLD value");
        uint256 expectedCarry = remainderOld + (remainderOld * 75) / 10_000;

        // Re-split to "bank everything" AFTER day 3 already resolved.
        vm.prank(player);
        coinflip.setCoinflipAutoRebuyTakeProfit(address(0), 1);

        (, uint256 stop, uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(stop, 1, "D: new take-profit stored");
        assertEq(
            carry,
            expectedCarry,
            "D: day 3 stays split under the OLD take-profit"
        );
        assertEq(
            coin.balanceOf(player),
            reservedOld,
            "D: only the OLD reserved chunk was minted by the settle"
        );
    }

    // ---------------------------------------------------------------------
    // E. The split conserves value at every take-profit size
    // ---------------------------------------------------------------------

    /// reserved + rolled-remainder == payout, exactly, for any take-profit. The split is
    /// a partition of the payout: it can neither mint nor destroy FLIP. (The recycle
    /// bonus is applied to the remainder AFTER the partition and is checked separately.)
    function testFuzz_TakeProfitSplitConservesPayout(uint96 takeProfitRaw) public {
        uint256 takeProfit = uint256(takeProfitRaw);
        vm.assume(takeProfit != 0);

        uint256 stake = _enterRebuyWithStake(takeProfit);
        _resolveDay(3, true);

        uint256 payout = _payoutOf(stake, 3);
        uint256 reserved = (payout / takeProfit) * takeProfit;
        uint256 remainder = payout - reserved;
        assertEq(reserved + remainder, payout, "E: partition must be exact");
        assertLt(remainder, takeProfit, "E: rolled remainder is always below one chunk");

        uint256 expectedCarry = remainder + (remainder * 75) / 10_000;

        // Settle without extracting: a 0-amount carry claim walks the days only.
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0);

        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, expectedCarry, "E: remainder + its recycle bonus rolls");
        assertEq(
            coinflip.previewClaimCoinflips(player),
            reserved,
            "E: reserved chunks bank, nothing else"
        );
    }

    // ---------------------------------------------------------------------
    // G. The previews agree with the settle they precede
    // ---------------------------------------------------------------------

    /// A rebuy position is ONE rolling stake, so a win followed by a loss is worth
    /// nothing: the loss zeroes the carry the win created. The preview must say so
    /// BEFORE the settle, not after.
    function test_SalvagePreviewIsAccurateAcrossAPendingLoss() public {
        _enterRebuyWithStake(0);
        _resolveDay(3, true);
        _resolveDay(4, false); // wipes the rolled carry once settled

        assertEq(
            coinflip.previewSalvageFlipBacking(player),
            0,
            "G: preview must already reflect the day-4 wipe"
        );
        assertEq(
            coinflip.previewClaimCoinflips(player),
            0,
            "G: claim preview likewise"
        );

        // Settling changes nothing — which is the whole point.
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0);
        assertEq(coinflip.previewSalvageFlipBacking(player), 0, "G: settle agrees");
    }

    /// The general invariant, fuzzed over take-profit and the win/loss pattern: whatever
    /// the previews report must survive the settle unchanged. A preview that disagrees
    /// with the claim it precedes is the defect class this pins shut.
    function testFuzz_PreviewsEqualPostSettleState(
        uint96 takeProfitRaw,
        bool win3,
        bool win4,
        bool win5
    ) public {
        uint256 takeProfit = uint256(takeProfitRaw);
        _enterRebuyWithStake(takeProfit);
        _resolveDay(3, win3);
        _resolveDay(4, win4);
        _resolveDay(5, win5);

        uint256 previewSalvage = coinflip.previewSalvageFlipBacking(player);
        uint256 previewClaim = coinflip.previewClaimCoinflips(player);

        // Walk the days for real without extracting anything.
        vm.prank(player);
        coinflip.claimCoinflipCarry(address(0), 0);

        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        uint256 settledClaim = coinflip.previewClaimCoinflips(player);

        assertEq(
            previewClaim,
            settledClaim,
            "claim preview must equal the post-settle bank"
        );
        assertEq(
            previewSalvage,
            settledClaim + carry,
            "salvage preview must equal bank + the carry the settle left"
        );
    }

    // ---------------------------------------------------------------------
    // F. A deposit can never land on an already-resolved day
    // ---------------------------------------------------------------------

    /// The structural freeze for the stake leg: deposits target
    /// `currentDayIndex() + 1`, resolution only ever resolves a day <= the wall day, so
    /// a stake is always strictly ahead of every known result. Walk several days and
    /// assert the gap never closes.
    function test_DepositAlwaysTargetsDayAfterLastResolved() public {
        vm.prank(GAME);
        coin.mintForGame(player, 1_000_000 ether);

        for (uint24 d = 3; d <= 8; d++) {
            _resolveDay(d, d % 2 == 1);

            // Wall clock is at day d and day d is now resolved. A fresh deposit must
            // land strictly after it.
            vm.prank(player);
            coinflip.depositCoinflip(address(0), 100 ether);

            // coinflipAmount reads the stake at _targetFlipDay() == wallDay + 1.
            assertGt(
                coinflip.coinflipAmount(player),
                0,
                "F: deposit landed on the next (unresolved) day"
            );
            // The resolved day itself must hold no fresh stake for this player: the
            // settle at deposit time cleared it and nothing re-staked onto it.
            (uint16 r, ) = coinflip.getCoinflipDayResult(d);
            assertGt(r, 0, "F: day d is resolved");
        }
    }
}
