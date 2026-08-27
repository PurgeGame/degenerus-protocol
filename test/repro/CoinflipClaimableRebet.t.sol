// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipClaimableRebet — the deposit funding waterfall and the recycling bonus basis
/// @notice A coinflip deposit funds itself from the player's settled winnings FIRST and burns
///         wallet FLIP only for the remainder; the 0.75% recycling bonus pays on the winnings
///         leg alone. Proves:
///         1. REBET      — a player whose whole position is claimable can rebet it with a ZERO
///                         wallet balance, and the bonus pays on the recycled amount.
///         2. BASIS      — the bonus keys on the claimable ACTUALLY DRAWN, not on the deposit
///                         and not on the whole bank: a partial draw leaves the rest banked and
///                         scales the bonus down with it. The rate is flat, so splitting a
///                         recycle across deposits earns exactly what one deposit earns.
///         3. FRESH      — a wallet-funded deposit by a player with no bank pays NO bonus.
///         4. MIXED      — claimable partially covers the deposit: the wallet burns exactly the
///                         shortfall and only the claimable leg earns the bonus.
///         5. GIFT       — a permissionless gift funds the whole stake from the caller and
///                         leaves the player's bank untouched (no forced wager, no bonus).
///         6. SUPPLY     — a fully claimable-funded rebet is supply-neutral: claimableStored is
///                         unminted and a day stake is off-supply, so nothing mints or burns.
///         7. RECORD     — a claimable-funded self-deposit is biggest-flip-record eligible.
/// @dev The fixture deposit is OPERATOR-ROUTED (indirect), so it cannot set the biggest-flip
///      record. That matters: a record claim pays its pool share as an extra stake on
///      _targetFlipDay() at deposit time — the very day these tests assert on — which would
///      silently pad the stake assertions. (A first arm only bootstraps and pays nothing,
///      but staying off the record entirely keeps the fixtures inert.)
contract CoinflipClaimableRebet is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    uint256 internal constant RECYCLE_BPS = 75;

    address internal player;
    address internal gifter;
    address internal operator;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("rebet_player");
        gifter = makeAddr("rebet_gifter");
        operator = makeAddr("rebet_operator");
        // Wall clock at day 2 so deposits target day 3 (clear of the day-1/2 emission seeds).
        _warpToDay(2);
        vm.prank(player);
        game.setOperatorApproval(operator, true);
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

    /// @dev Resolve day `epoch` as the GAME with a win or loss word, wall clock at `epoch`.
    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 word = uint256(keccak256(abi.encodePacked("rebet_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }

    function _recyclingBonus(uint256 amount) internal pure returns (uint256 bonus) {
        bonus = (amount * RECYCLE_BPS) / 10_000;
    }

    /// @dev Stake `amount` for `player` on day 3 out of a freshly minted wallet balance, then win
    ///      day 3. Leaves the player with a ZERO wallet balance and the whole payout sitting as
    ///      unclaimed winnings — the position the rebet path exists to serve.
    function _bankAWin(uint256 amount) internal returns (uint256 payout) {
        vm.prank(GAME);
        coin.mintForGame(player, amount);
        // Operator-routed: indirect, so it arms neither the bounty nor the biggest-flip record.
        vm.prank(operator);
        coinflip.depositCoinflip(player, amount);
        assertEq(coin.balanceOf(player), 0, "fixture: deposit burned the whole wallet balance");
        assertEq(coinflip.biggestFlipEver(), 0, "fixture: indirect deposit set no record");

        _resolveDay(3, true);
        (uint16 r, bool win) = coinflip.getCoinflipDayResult(3);
        assertTrue(win, "fixture: day 3 must be a win");
        payout = amount + (amount * uint256(r)) / 100;
        assertEq(coinflip.previewClaimCoinflips(player), payout, "fixture: payout is claimable");
        assertEq(coinflip.coinflipAmount(player), 0, "fixture: day 4 starts empty");
    }

    // ---------------------------------------------------------------- 1. REBET

    function test_RebetSpendsClaimableWithZeroWalletAndPaysBonus() public {
        uint256 payout = _bankAWin(100_000 ether);

        // This payout clears the 200,000-FLIP record floor, so the deposit is also the
        // first-ever biggest-flip mark and claims its launch-accrued pool share into the
        // same day stake. Measure that share off the pool decrement and account for it
        // separately, so the recycle arithmetic stays the thing under test.
        uint256 poolBefore = coinflip.recordPool();

        // The whole deposit is funded from the bank — the player holds no FLIP at all.
        vm.prank(player);
        coinflip.depositCoinflip(address(0), payout);

        uint256 recordClaim = poolBefore - coinflip.recordPool();
        assertGt(recordClaim, 0, "fixture: the deposit bootstrapped the flip record");

        assertEq(coin.balanceOf(player), 0, "no wallet FLIP was needed or minted");
        assertEq(coinflip.previewClaimCoinflips(player), 0, "the bank funded the whole stake");
        assertEq(
            coinflip.coinflipAmount(player),
            payout + _recyclingBonus(payout) + recordClaim,
            "recycled principal plus its 0.75% bonus rides day 4 (beside the record claim)"
        );
    }

    // ---------------------------------------------------------------- 2. BASIS

    function test_BonusScalesWithTheClaimableActuallyDrawn() public {
        uint256 payout = _bankAWin(10_000 ether);
        uint256 draw = 10_000 ether;
        assertLt(draw, payout, "fixture: draw only part of the bank");

        vm.prank(player);
        coinflip.depositCoinflip(address(0), draw);

        assertEq(
            coinflip.previewClaimCoinflips(player),
            payout - draw,
            "only the drawn slice left the bank"
        );
        assertEq(
            coinflip.coinflipAmount(player),
            draw + _recyclingBonus(draw),
            "bonus keys on the drawn slice, not on the whole bank"
        );
    }

    function test_FullDrawBonusesTheWholePayout() public {
        uint256 payout = _bankAWin(10_000 ether);

        vm.prank(player);
        coinflip.depositCoinflip(address(0), payout);

        assertEq(
            coinflip.coinflipAmount(player),
            payout + _recyclingBonus(payout),
            "the full recycled payout earns the flat 0.75%"
        );
    }

    /// @notice The bonus is a flat rate, so splitting a recycle across several deposits earns
    ///         exactly what recycling it in one deposit earns. Nothing is gained or lost by
    ///         chunking, and the same percentage reaches a whale and a minnow.
    function test_SplittingARecycleEarnsTheSameAsOneDeposit() public {
        uint256 payout = _bankAWin(100_000 ether);
        uint256 half = payout / 2;
        assertEq(half * 2, payout, "fixture: payout splits evenly");

        vm.startPrank(player);
        coinflip.depositCoinflip(address(0), half);
        coinflip.depositCoinflip(address(0), payout - half);
        vm.stopPrank();

        assertEq(coinflip.previewClaimCoinflips(player), 0, "both halves drew the bank");
        assertEq(
            _recyclingBonus(half) * 2,
            _recyclingBonus(payout),
            "the rate is size-independent: two halves bonus exactly as one whole"
        );
        assertEq(
            coinflip.coinflipAmount(player),
            payout + _recyclingBonus(payout),
            "split recycling earns no more and no less than a single deposit"
        );
    }

    // ---------------------------------------------------------------- 3. FRESH

    function test_WalletFundedDepositWithNoBankPaysNoBonus() public {
        uint256 amount = 100_000 ether;
        vm.prank(GAME);
        coin.mintForGame(player, amount);

        vm.prank(player);
        coinflip.depositCoinflip(address(0), amount);

        assertEq(coin.balanceOf(player), 0, "wallet funded the whole stake");
        assertEq(
            coinflip.coinflipAmount(player),
            amount,
            "fresh money earns no recycling bonus"
        );
    }

    // ---------------------------------------------------------------- 4. MIXED

    function test_MixedFundingBurnsOnlyTheShortfallAndBonusesTheBankLeg() public {
        uint256 payout = _bankAWin(10_000 ether);
        uint256 topUp = 40_000 ether;
        uint256 amount = payout + topUp;

        vm.prank(GAME);
        coin.mintForGame(player, topUp);
        uint256 supplyBefore = coin.totalSupply();

        vm.prank(player);
        coinflip.depositCoinflip(address(0), amount);

        assertEq(coin.balanceOf(player), 0, "the wallet leg burned exactly the shortfall");
        assertEq(
            supplyBefore - coin.totalSupply(),
            topUp,
            "only the wallet leg left supply; the bank leg was already unminted"
        );
        assertEq(coinflip.previewClaimCoinflips(player), 0, "the bank leg was fully drawn");
        assertEq(
            coinflip.coinflipAmount(player),
            amount + _recyclingBonus(payout),
            "bonus keys on the recycled leg, not the wallet-funded remainder"
        );
    }

    // ---------------------------------------------------------------- 5. GIFT

    function test_GiftFundsFromCallerAndLeavesThePlayersBankAlone() public {
        uint256 payout = _bankAWin(100_000 ether);
        uint256 gift = 5_000 ether;

        vm.prank(GAME);
        coin.mintForGame(gifter, gift);

        // gifter is NOT the player and NOT an approved operator.
        vm.prank(gifter);
        coinflip.depositCoinflip(player, gift);

        assertEq(coin.balanceOf(gifter), 0, "the gifter's own FLIP funded the stake");
        assertEq(
            coinflip.previewClaimCoinflips(player),
            payout,
            "a non-consenting player's bank is never pushed onto a flip"
        );
        assertEq(
            coinflip.coinflipAmount(player),
            gift,
            "gift is wallet-only, so it earns no recycling bonus"
        );
    }

    function test_ApprovedOperatorMayDrawThePlayersBank() public {
        uint256 payout = _bankAWin(100_000 ether);

        vm.prank(operator);
        coinflip.depositCoinflip(player, payout);

        assertEq(coinflip.previewClaimCoinflips(player), 0, "operator approval reaches the bank");
        assertEq(
            coinflip.coinflipAmount(player),
            payout + _recyclingBonus(payout),
            "operator-routed rebet earns the recycling bonus too"
        );
    }

    // ------------------------------------------------------- 5b. AUTO-REBUY BUCKETS

    /// @notice An auto-rebuy player's deposit draws the TAKE-PROFIT BANK (claimableStored) and
    ///         bonuses that draw. The rolling carry is a separate bucket the deposit never
    ///         touches — it earns its own bonus where it rolls, inside the settle walk.
    function test_AutoRebuyDepositDrawsTheBankAndLeavesTheCarryAlone() public {
        uint256 stake = 100_000 ether;
        uint256 takeProfit = 100_000 ether;

        vm.prank(GAME);
        coin.mintForGame(player, stake);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), true, takeProfit);
        vm.prank(operator);
        coinflip.depositCoinflip(player, stake);

        _resolveDay(3, true);
        (uint16 r, ) = coinflip.getCoinflipDayResult(3);
        uint256 payout = stake + (stake * uint256(r)) / 100;
        uint256 reserved = (payout / takeProfit) * takeProfit;
        uint256 rolled = payout - reserved;
        uint256 expectedCarry = rolled + _recyclingBonus(rolled);

        // Settle-only probe: banks the take-profit chunk and rolls the remainder as carry.
        vm.prank(player);
        coinflip.depositCoinflip(address(0), 0);
        assertEq(coinflip.previewClaimCoinflips(player), reserved, "take-profit banked");
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, expectedCarry, "remainder rolled into the carry");

        uint256 draw = 50_000 ether;

        vm.prank(player);
        coinflip.depositCoinflip(address(0), draw);

        assertEq(
            coinflip.previewClaimCoinflips(player),
            reserved - draw,
            "the deposit drew the take-profit bank"
        );
        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryAfter, expectedCarry, "the carry is a separate bucket, untouched");
        assertEq(
            coinflip.coinflipAmount(player),
            draw + _recyclingBonus(draw),
            "the drawn bank leg earns the recycling bonus"
        );
    }

    /// @notice The claimable leg is NOT a back door around the carry's RNG-lock guard. Under the
    ///         lock a deposit still funds from the take-profit bank only, still lands on TOMORROW
    ///         (whose word cannot exist yet), and still leaves the carry — the pending day's live
    ///         stake — untouched, while every carry-extraction entrypoint stays shut. Value only
    ///         moves further ONTO the table here; nothing can be pulled off it.
    /// @dev Driven through the real freeze rather than a mocked flag: the carry gates read
    ///      Coinflip's own settlement marker (`flipsClaimableDay < currentDayIndex()`), not the
    ///      game's `rngLocked()`, so warping past the resolved day is what shuts them. The error
    ///      they raise is still `RngLocked`. Level is 0 here, so
    ///      `_coinflipLockedDuringTransition`'s x10 gate is false either way.
    function test_DepositUnderRngLockCannotReachTheCarry() public {
        uint256 stake = 100_000 ether;
        uint256 takeProfit = 100_000 ether;

        vm.prank(GAME);
        coin.mintForGame(player, stake);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(address(0), true, takeProfit);
        vm.prank(operator);
        coinflip.depositCoinflip(player, stake);

        _resolveDay(3, true);
        vm.prank(player);
        coinflip.depositCoinflip(address(0), 0); // settle: banks take-profit, rolls the carry
        uint256 bankBefore = coinflip.previewClaimCoinflips(player);
        (, , uint256 carryBefore, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertGt(bankBefore, 0, "fixture: a take-profit bank exists");
        assertGt(carryBefore, 0, "fixture: a live carry exists");

        _warpToDay(4); // day 4 unapplied: the carry freeze is on

        // Every path that could pull the carry off the table stays shut.
        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        coinflip.claimCoinflipCarry(address(0), type(uint256).max);
        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        coinflip.setCoinflipAutoRebuy(address(0), false, 0);

        // The deposit is still open, and it can only push MORE onto tomorrow's flip.
        uint256 draw = 50_000 ether;
        vm.prank(player);
        coinflip.depositCoinflip(address(0), draw);

        assertEq(
            coinflip.previewClaimCoinflips(player),
            bankBefore - draw,
            "the deposit drew the bank, and only the bank"
        );
        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryAfter, carryBefore, "the live carry is unreachable from the deposit path");
        assertEq(
            coinflip.coinflipAmount(player),
            draw + _recyclingBonus(draw),
            "the stake landed on tomorrow, whose word cannot exist yet"
        );
        assertEq(
            coinflip.biggestFlipEver(),
            0,
            "a 50k deposit sits under the 200k record floor and stays off the record"
        );
    }

    // ---------------------------------------------------------------- 6. SUPPLY

    function test_FullyRecycledRebetIsSupplyNeutral() public {
        uint256 payout = _bankAWin(100_000 ether);
        uint256 supplyBefore = coin.totalSupply();

        vm.prank(player);
        coinflip.depositCoinflip(address(0), payout);

        assertEq(
            coin.totalSupply(),
            supplyBefore,
            "moving unminted claimable onto an off-supply stake mints and burns nothing"
        );
    }

    // ---------------------------------------------------------------- 7. BOUNTY

    function test_ClaimableFundedSelfDepositIsRecordEligible() public {
        // Bank enough that the payout clears the 200k FLIP record entry floor.
        uint256 payout = _bankAWin(200_000 ether);
        assertGt(payout, 200_000 ether, "fixture: the payout must clear the floor");

        vm.prank(player);
        coinflip.depositCoinflip(address(0), payout);

        assertEq(
            coinflip.biggestFlipEver(),
            payout,
            "a rebet is a real wager: it sets the biggest-flip record"
        );
    }
}
