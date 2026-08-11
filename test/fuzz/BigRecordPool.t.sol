// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {
    RECORD_KIND_SPIN,
    RECORD_KIND_LUCKBOX
} from "../../contracts/interfaces/ICoinflip.sol";

/// @title BigRecordPoolTest — pins the unified all-time record pool in Coinflip.
///
/// @notice Four records (flip deposit, degenerette spin, lootbox deposit, ticket buy)
///         share one FLIP pool and one ruleset: a candidate larger than the standing
///         mark ratchets it for free; clearing the mark by a FIFTH claims an accruing
///         share of the pool — 5% floor, +0.5% per day the record's own category has
///         gone unclaimed, capped at 75% — credited as next-day flip stake, never a
///         wallet mint. Claims also pay an sDGNRS leg (same share at 1/500 scale of
///         the sDGNRS reward pool) via the game.
///
/// @dev The behaviours pinned here are the ones a refactor would quietly break:
///      - Every category clock is constructor-seeded to the deploy day, so a
///        category's FIRST claim draws the share accrued since launch — and a
///        bootstrap restamps its category's clock like any claim. An unstamped zero
///        would read the whole day index as elapsed and max the next claim's share.
///      - A bare ratchet (larger, but under +20%) must NOT restamp the clock.
///      - Each category accrues on its OWN clock: one category's claim leaves the
///        other categories' accrual untouched.
///      - The claim credit re-enters the stake path with recordAmount = 0, so a big
///        claim can never re-arm the flip record off its own payout.
///      - The flip record arms on DIRECT self-deposits only, at or above the 200k
///        FLIP entry floor.
///      All assertions are behavioural (getters, stakes, pool balances) — nothing
///      here pins a storage slot.
contract BigRecordPoolTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;

    uint256 internal constant FLIP_MIN = 200_000 ether;
    uint256 internal constant SHARE_FLOOR_BPS = 500;
    uint256 internal constant SHARE_PER_DAY_BPS = 50;
    uint256 internal constant SHARE_CEIL_BPS = 7_500;
    uint256 internal constant DAILY_DRIP = 2_000 ether;
    uint256 internal constant POOL_SEED = 10_000 ether;

    address private player;
    address private rival;
    address private operator;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("record_player");
        rival = makeAddr("record_rival");
        operator = makeAddr("record_operator");
        // Wall clock at day 2 so deposits target day 3 (clear of the day-1/2 seeds).
        _warpToDay(2);
        vm.prank(player);
        game.setOperatorApproval(operator, true);
    }

    // ---------------------------------------------------------------------
    // Pool basics
    // ---------------------------------------------------------------------

    function testPoolSeedsAtTenThousand() public view {
        assertEq(coinflip.recordPool(), POOL_SEED, "pool seeds at 10,000 FLIP");
    }

    /// @notice Every settled day drips 2,000 FLIP into the pool.
    function testSettlementDripsIntoPool() public {
        uint256 before = coinflip.recordPool();
        _resolveDay(2, true);
        assertEq(
            coinflip.recordPool(),
            before + DAILY_DRIP,
            "settlement drips 2,000 FLIP"
        );
    }

    function testFundRecordPoolIsGameOnly() public {
        vm.prank(player);
        vm.expectRevert();
        coinflip.fundRecordPool(1 ether);

        uint256 before = coinflip.recordPool();
        vm.prank(GAME);
        coinflip.fundRecordPool(123 ether);
        assertEq(coinflip.recordPool(), before + 123 ether, "game funding lands");
    }

    /// @notice A push past uint128 clamps at the width instead of wrapping to dust.
    function testFundRecordPoolClampsAtWidth() public {
        vm.prank(GAME);
        coinflip.fundRecordPool(type(uint128).max);
        assertEq(
            coinflip.recordPool(),
            type(uint128).max,
            "oversized funding clamps, never wraps"
        );
    }

    // ---------------------------------------------------------------------
    // armRecord surface
    // ---------------------------------------------------------------------

    function testArmRecordIsGameOnly() public {
        vm.prank(player);
        vm.expectRevert();
        coinflip.armRecord(RECORD_KIND_SPIN, player, 1 ether);
    }

    // ---------------------------------------------------------------------
    // Ratchet vs claim (spin kind via armRecord — the shared path)
    // ---------------------------------------------------------------------

    /// @notice The first qualifying candidate has no bar to clear and draws the share
    ///         accrued since deploy — the constructor starts every clock on day 1, so
    ///         a day-2 bootstrap pays the floor plus one day.
    function testBootstrapClaimsTheShareAccruedSinceDeploy() public {
        uint256 poolBefore = coinflip.recordPool();
        uint256 expected = (poolBefore *
            (SHARE_FLOOR_BPS + 1 * SHARE_PER_DAY_BPS)) / 10_000;
        uint256 claim = _arm(RECORD_KIND_SPIN, player, 10 ether);

        assertEq(coinflip.biggestSpinEver(), 10 ether, "bootstrap sets the mark");
        assertEq(
            coinflip.recordPool(),
            poolBefore - expected,
            "bootstrap draws the accrued share"
        );
        assertEq(claim, expected, "the accrued share is handed back to the caller");
    }

    /// @notice A category untouched since launch accrues on the deploy-seeded clock:
    ///         the very first hit on day 12 pays 5% + 11 days at 0.5%.
    function testFirstClaimAccruesFromDeploy() public {
        _warpToDay(12);
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * (SHARE_FLOOR_BPS + 11 * SHARE_PER_DAY_BPS)) /
            10_000;

        assertEq(
            _arm(RECORD_KIND_SPIN, player, 10 ether),
            expected,
            "a dormant category's first hit pays the launch-accrued share"
        );
    }

    /// @notice Under +20% ratchets the mark for free; the pool is untouched.
    function testSubFifthRatchetIsFree() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);
        uint256 poolBefore = coinflip.recordPool();

        // +19.9%, under the fifth
        uint256 claim = _arm(RECORD_KIND_SPIN, rival, 11.99 ether);

        assertEq(coinflip.biggestSpinEver(), 11.99 ether, "ratchet still moves the mark");
        assertEq(coinflip.recordPool(), poolBefore, "ratchet claims nothing");
        assertEq(claim, 0, "a ratchet hands back nothing");
    }

    /// @notice At exactly +20% the candidate claims the floor share the same day.
    function testClaimAtExactFifthPaysFloorShare() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_FLOOR_BPS) / 10_000;

        // exactly mark + mark/5
        uint256 claim = _arm(RECORD_KIND_SPIN, rival, 12 ether);

        assertEq(coinflip.biggestSpinEver(), 12 ether, "claim ratchets the mark");
        assertEq(coinflip.recordPool(), pool - expected, "pool pays the floor share");
        assertEq(claim, expected, "the floor share is handed back to the caller");
    }

    /// @notice The share accrues +0.5%/day on the category's clock.
    function testShareAccruesPerDay() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);

        _warpToDay(12); // 10 days after the day-2 bootstrap
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * (SHARE_FLOOR_BPS + 10 * SHARE_PER_DAY_BPS)) /
            10_000;

        assertEq(
            _arm(RECORD_KIND_SPIN, rival, 12 ether),
            expected,
            "10 unhit days pay 10% of the pool"
        );
    }

    /// @notice The share clamps at 75% (day 140) rather than growing without bound.
    function testShareClampsAtCeiling() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);

        _warpToDay(202); // 200 days unhit, far past the day-140 cap
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_CEIL_BPS) / 10_000;

        assertEq(
            _arm(RECORD_KIND_SPIN, rival, 12 ether),
            expected,
            "share clamps at 75%"
        );
    }

    /// @notice A bare ratchet must not restamp the clock — the later claim still pays
    ///         the full accrual measured from the bootstrap.
    function testBareRatchetDoesNotRestampClock() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);

        _warpToDay(12);
        _arm(RECORD_KIND_SPIN, rival, 11 ether); // +10%: ratchet only

        _warpToDay(22); // 20 days since bootstrap, 10 since the ratchet
        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * (SHARE_FLOOR_BPS + 20 * SHARE_PER_DAY_BPS)) /
            10_000;

        // clears 11 by well over a fifth
        assertEq(
            _arm(RECORD_KIND_SPIN, player, 14 ether),
            expected,
            "accrual runs 20 days from bootstrap, not 10 from the ratchet"
        );
    }

    /// @notice A claim restamps its OWN category's clock: a same-day follow-up claim
    ///         pays only the floor.
    function testClaimResetsOwnClock() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);

        _warpToDay(32);
        _arm(RECORD_KIND_SPIN, rival, 12 ether); // claims 5% + 30 days' accrual

        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_FLOOR_BPS) / 10_000;
        // same day, clears 12 by a fifth
        assertEq(
            _arm(RECORD_KIND_SPIN, player, 15 ether),
            expected,
            "a claim resets its category to the floor"
        );
    }

    /// @notice Categories accrue independently: one category's claim leaves another's
    ///         clock untouched.
    function testCategoriesKeepIndependentClocks() public {
        _arm(RECORD_KIND_SPIN, player, 10 ether);
        _arm(RECORD_KIND_LUCKBOX, player, 10 ether);

        _warpToDay(12); // both clocks at 10 unhit days
        uint256 pool = coinflip.recordPool();
        uint256 spinShare = (pool * (SHARE_FLOOR_BPS + 10 * SHARE_PER_DAY_BPS)) /
            10_000;
        assertEq(
            _arm(RECORD_KIND_SPIN, rival, 12 ether),
            spinShare,
            "spin pays 10%"
        );

        // The luckbox clock did not restamp on the spin claim: it still pays 30%
        // of what remains, not the 20% floor.
        uint256 remaining = coinflip.recordPool();
        uint256 boxShare = (remaining *
            (SHARE_FLOOR_BPS + 10 * SHARE_PER_DAY_BPS)) / 10_000;
        assertEq(
            _arm(RECORD_KIND_LUCKBOX, player, 12 ether),
            boxShare,
            "the spin claim left the luckbox clock alone"
        );
    }

    // ---------------------------------------------------------------------
    // Flip record (internal arming via direct deposits)
    // ---------------------------------------------------------------------

    /// @notice A direct self-deposit at the floor bootstraps the flip record.
    function testDirectDepositAtFloorArmsFlipRecord() public {
        _selfDeposit(player, FLIP_MIN);
        assertEq(
            coinflip.biggestFlipEver(),
            FLIP_MIN,
            "a floor deposit bootstraps the record"
        );
    }

    /// @notice A deposit under the floor never arms, however large the standing pool.
    function testSubFloorDepositNeverArms() public {
        _selfDeposit(player, FLIP_MIN - 1 ether);
        assertEq(coinflip.biggestFlipEver(), 0, "sub-floor deposit never arms");
    }

    /// @notice An operator-routed (indirect) deposit never arms the record.
    function testIndirectDepositNeverArms() public {
        vm.prank(GAME);
        coin.mintForGame(player, FLIP_MIN);
        vm.prank(operator);
        coinflip.depositCoinflip(player, FLIP_MIN);
        assertEq(coinflip.biggestFlipEver(), 0, "indirect deposits stay off the record");
    }

    /// @notice A flip claim pays the accrued share on top of the deposit's own stake.
    function testFlipClaimPaysShareOnTopOfStake() public {
        _selfDeposit(player, FLIP_MIN);

        uint256 pool = coinflip.recordPool();
        uint256 expected = (pool * SHARE_FLOOR_BPS) / 10_000;
        uint256 claimAmount = FLIP_MIN + FLIP_MIN / 5; // exactly +20%

        _selfDeposit(rival, claimAmount);
        assertEq(coinflip.biggestFlipEver(), claimAmount, "claim ratchets the record");
        assertEq(
            coinflip.coinflipAmount(rival),
            claimAmount + expected,
            "stake carries the deposit plus the claimed share"
        );
        assertEq(coinflip.recordPool(), pool - expected, "pool paid the share");
    }

    /// @notice Every credit path enters the stake path with recordAmount = 0 (only a
    ///         direct deposit's raw amount arms), so a payout larger than the standing
    ///         mark can never re-arm the record.
    function testClaimCreditCannotRearmFlipRecord() public {
        _selfDeposit(player, FLIP_MIN);

        // Inflate the pool so the floor share (20%) dwarfs the next mark.
        vm.prank(GAME);
        coinflip.fundRecordPool(10_000_000 ether);

        uint256 claimAmount = FLIP_MIN + FLIP_MIN / 5;
        _selfDeposit(rival, claimAmount);

        uint256 paid = coinflip.coinflipAmount(rival) - claimAmount;
        assertGt(paid, claimAmount, "fixture: the credit exceeds the new mark");
        assertEq(
            coinflip.biggestFlipEver(),
            claimAmount,
            "the credit did not re-arm the record"
        );
    }

    // ---------------------------------------------------------------------
    // sDGNRS leg
    // ---------------------------------------------------------------------

    function testPayRecordSdgnrsIsCoinflipOnly() public {
        vm.prank(player);
        vm.expectRevert();
        game.payRecordSdgnrs(player, SHARE_CEIL_BPS);
    }

    /// @notice The leg pays the accrued share at 1/500 scale of the live reward pool
    ///         (zero on an empty pool), and never reverts the claim.
    function testPayRecordSdgnrsPaysScaledShare() public {
        uint256 rewardPool = IsDGNRS(ContractAddresses.SDGNRS).poolBalance(
            IsDGNRS.Pool.Reward
        );
        uint256 expected = (rewardPool * SHARE_CEIL_BPS) / (10_000 * 500);

        vm.prank(ContractAddresses.COINFLIP);
        uint256 paid = game.payRecordSdgnrs(player, SHARE_CEIL_BPS);
        assertEq(paid, expected, "the leg pays shareBps of rewardPool/500");
    }

    // The BAF weighted-draw surface (the top-day-bettor board's replacement) is
    // pinned in test/fuzz/BafWeightedDraw.t.sol; this suite keeps only the record
    // behaviours.

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev Wall clock just inside GameTimeLib day `d`.
    function _warpToDay(uint24 d) internal {
        vm.warp(
            (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
    }

    /// @dev Resolve day `epoch` as the GAME, wall clock at `epoch`.
    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 word = uint256(keccak256(abi.encodePacked("record_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }

    /// @dev Arm a game-side record as the GAME, returning the claim it hands back.
    ///      Coinflip credits nothing itself — the arming module folds the claim into
    ///      the FLIP its own path already pays — so the return IS the payout under test.
    function _arm(
        uint8 kind,
        address who,
        uint256 candidate
    ) internal returns (uint256) {
        vm.prank(GAME);
        return coinflip.armRecord(kind, who, candidate);
    }

    /// @dev Mint wallet FLIP and self-deposit it (direct — arms the flip record).
    function _selfDeposit(address who, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame(who, amount);
        vm.prank(who);
        coinflip.depositCoinflip(address(0), amount);
    }
}
