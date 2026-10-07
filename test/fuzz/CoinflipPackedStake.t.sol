// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @dev Exposes the stake codec for lane-level checks. Deployed off the pinned address, so it
///      shares nothing with the protocol fixture.
contract CoinflipCodecHarness is CoinflipStakeSetter {
    function setStake(uint24 day, uint32 p, uint256 weiAmount) external returns (uint256) {
        return _setFlipStake(day, p, weiAmount);
    }

    function stake(uint24 day, uint32 p) external view returns (uint256) {
        return _flipStake(day, p);
    }

    function word(uint24 key, uint32 p) external view returns (uint256) {
        return coinflipStakePacked[key][p];
    }
}

/// @title CoinflipPackedStake — eight whole-FLIP uint32 lanes per stake word
/// @notice Pins the stake codec (key = day >> 3, lane = (day & 7) * 32, whole FLIP) and the
///         accounting rules every stake-writing route follows: whole-FLIP flooring once per
///         addition, saturation at the per-player-day cap for automatic credits, a dedicated
///         revert for manual deposits over the cap, and CoinflipStakeUpdated reporting the
///         stake actually accepted.
contract CoinflipPackedStake is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant COIN = ContractAddresses.COIN;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;

    uint256 internal constant UNIT = 1;
    uint256 internal constant LANE_MAX = type(uint32).max;
    uint256 internal constant CAP = LANE_MAX * UNIT;
    uint256 internal constant SEED = 200_000;
    bytes32 internal constant STAKE_SIG = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    CoinflipCodecHarness internal codec;
    address internal player;
    address internal operator;
    address internal gifter;
    uint32 internal playerId;

    function setUp() public {
        _deployProtocol();
        codec = new CoinflipCodecHarness();
        player = makeAddr("packed_player");
        operator = makeAddr("packed_operator");
        gifter = makeAddr("packed_gifter");
        playerId = _giveWalletId(player);
        vm.prank(player);
        game.setOperatorApproval(0, operator, true);
        _warpToDay(2);
    }

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    function _targetDay() internal view returns (uint24) {
        return GameTimeLib.currentDayIndex() + 1;
    }

    /// @dev Raw lane read against the production contract: slot 0, key day >> 3, 32-bit lanes.
    function _rawStake(uint24 day, address p) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(day >> 3), uint256(0)));
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(p)), uint256(inner)));
        uint256 w = uint256(vm.load(address(coinflip), slot));
        return uint256(uint32(w >> ((uint256(day) & 7) * 32))) * UNIT;
    }

    function _whole(uint256 x) internal pure returns (uint256) {
        return (x / UNIT) * UNIT;
    }

    function _mint(address to, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame(to, amount);
    }

    function _credit(address p, uint256 amount) internal {
        uint32 id = _giveWalletId(p);
        vm.prank(GAME);
        coinflip.creditFlip(id, amount);
    }

    /// @dev The single CoinflipStakeUpdated for `p` in the recorded logs.
    function _stakeEvent(Vm.Log[] memory logs, address p) internal returns (uint24 day, uint256 amount, uint256 total) {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(coinflip) && logs[i].topics[0] == STAKE_SIG
                    && uint32(uint256(logs[i].topics[1])) == game.walletIdOf(p)
            ) {
                day = uint24(uint256(logs[i].topics[2]));
                (amount, total) = abi.decode(logs[i].data, (uint256, uint256));
                ++seen;
            }
        }
        assertEq(seen, 1, "exactly one stake event for the player");
    }

    // =====================================================================
    //                           1. CODEC
    // =====================================================================

    function test_EightLanesPerWordWithSlotBoundaries() public {
        uint32 p = 0xA11CE;
        // Days 16..31 span two words (keys 2 and 3): every lane holds its own value.
        for (uint24 d = 16; d < 32; ++d) {
            codec.setStake(d, p, uint256(d) * UNIT);
        }
        for (uint24 d = 16; d < 32; ++d) {
            assertEq(codec.stake(d, p), uint256(d) * UNIT, "lane holds its own day");
        }
        uint256 expected2;
        uint256 expected3;
        for (uint256 i; i < 8; ++i) {
            expected2 |= (16 + i) << (i * 32);
            expected3 |= (24 + i) << (i * 32);
        }
        assertEq(codec.word(2, p), expected2, "word 2 packs days 16..23 low to high");
        assertEq(codec.word(3, p), expected3, "word 3 packs days 24..31 low to high");
        assertEq(codec.stake(15, p), 0, "day 15 (word 1) untouched");
        assertEq(codec.stake(32, p), 0, "day 32 (word 4) untouched");

        // Zeroing one lane preserves its seven siblings.
        codec.setStake(19, p, 0);
        assertEq(codec.stake(19, p), 0);
        for (uint24 d = 16; d < 24; ++d) {
            if (d != 19) assertEq(codec.stake(d, p), uint256(d) * UNIT, "sibling lane survives a clear");
        }
    }

    function test_WritePreservesWholeFlipAndSaturates() public {
        uint32 p = 0xB0B;
        assertEq(codec.setStake(9, p, 1234), 1234, "write returns the stored whole FLIP");
        assertEq(codec.stake(9, p), 1234);
        assertEq(codec.setStake(9, p, 0), 0, "zero clears the lane");
        assertEq(codec.setStake(9, p, CAP), CAP, "the lane holds exactly type(uint32).max FLIP");
        assertEq(codec.setStake(9, p, CAP + UNIT), CAP, "one FLIP over the cap saturates");
        assertEq(codec.setStake(9, p, type(uint256).max), CAP, "an oversized input saturates");
        assertEq(codec.stake(8, p), 0, "the saturated lane spilled nowhere below");
        assertEq(codec.stake(10, p), 0, "the saturated lane spilled nowhere above");
    }

    function testFuzz_WriteTouchesOnlyItsOwnLaneAndPlayer(
        uint24 day,
        uint256 amount,
        uint24 otherDay,
        uint32 otherPlayer,
        uint256 otherAmount
    ) public {
        uint32 pid = _giveWalletId(player);
        vm.assume(otherPlayer != pid);
        vm.assume(day != otherDay);
        codec.setStake(otherDay, pid, otherAmount);
        codec.setStake(day, otherPlayer, otherAmount);
        uint256 expectedOtherDay = codec.stake(otherDay, pid);
        uint256 expectedOtherPlayer = codec.stake(day, otherPlayer);

        uint256 stored = codec.setStake(day, pid, amount);
        uint256 expected = amount / UNIT > LANE_MAX ? CAP : _whole(amount);
        assertEq(stored, expected, "stored = min(floor(amount), cap)");
        assertEq(codec.stake(day, pid), expected);
        assertEq(codec.stake(otherDay, pid), expectedOtherDay, "another day of the same player is untouched");
        assertEq(codec.stake(day, otherPlayer), expectedOtherPlayer, "the same day of another player is untouched");
        // Every lane except the written one is unchanged.
        for (uint24 i; i < 8; ++i) {
            uint24 sibling = (day & ~uint24(7)) | i;
            if (sibling == day) continue;
            if (sibling == otherDay) continue;
            assertEq(codec.stake(sibling, pid), 0, "sibling lane stays zero");
        }
    }

    // =====================================================================
    //                 2. AUTOMATIC CREDITS: floor + saturate
    // =====================================================================

    function test_IntegerCreditsPreserveUnitsWithExactEvents() public {
        uint24 day = _targetDay();
        vm.recordLogs();
        _credit(player, 1);
        (uint24 d, uint256 amount, uint256 total) = _stakeEvent(vm.getRecordedLogs(), player);
        assertEq(d, day);
        assertEq(amount, 1);
        assertEq(total, 1);
        _credit(player, 0);
        assertEq(coinflip.coinflipAmount(player), 1, "zero credit adds nothing");
        vm.recordLogs();
        _credit(player, 1001);
        (, amount, total) = _stakeEvent(vm.getRecordedLogs(), player);
        assertEq(amount, 1001);
        assertEq(total, 1002);
        assertEq(_rawStake(day, player), 1002, "raw lane agrees with the view");
    }

    function test_CreditSaturatesAtTheCapWithPartialAcceptance() public {
        _credit(player, CAP - UNIT);
        assertEq(coinflip.coinflipAmount(player), CAP - UNIT);

        vm.recordLogs();
        _credit(player, 5);
        (, uint256 amount, uint256 total) = _stakeEvent(vm.getRecordedLogs(), player);
        assertEq(amount, UNIT, "only the room left is accepted");
        assertEq(total, CAP);

        vm.recordLogs();
        _credit(player, 5);
        (, amount, total) = _stakeEvent(vm.getRecordedLogs(), player);
        assertEq(amount, 0, "a credit at the cap adds nothing but still reports");
        assertEq(total, CAP);
        assertEq(coinflip.coinflipAmount(player), CAP);
        assertEq(_rawStake(_targetDay() + 1, player), 0, "no spill into the next day");
    }

    function test_BatchAndPairDuplicatesCreditEachLeg() public {
        uint32[] memory players = new uint32[](2);
        uint256[] memory amounts = new uint256[](2);
        players[0] = _giveWalletId(player);
        players[1] = players[0];
        amounts[0] = 1;
        amounts[1] = 1;
        vm.prank(GAME);
        coinflip.creditFlipBatch(players, amounts);
        assertEq(coinflip.coinflipAmount(player), 2, "duplicate batch recipients accumulate both legs");

        vm.recordLogs();
        vm.prank(GAME);
        coinflip.creditFlipPair(players[0], 1, players[0], 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 events;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip) && logs[i].topics[0] == STAKE_SIG) {
                (uint256 amount, uint256 total) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(amount, 1, "each integer leg adds one token");
                assertEq(total, 3 + events);
                ++events;
            }
        }
        assertEq(events, 2, "both nonzero legs report");
        assertEq(coinflip.coinflipAmount(player), 4);

        // A recipient already at the cap never bricks a batch.
        _credit(player, CAP);
        vm.prank(GAME);
        coinflip.creditFlipBatch(players, amounts);
        assertEq(coinflip.coinflipAmount(player), CAP);
    }

    // =====================================================================
    //                 3. MANUAL DEPOSITS: normalize + cap revert
    // =====================================================================

    function test_SelfDepositSpendsExactIntegerPrincipal() public {
        _mint(player, 200);
        vm.recordLogs();
        vm.prank(player);
        coinflip.depositCoinflip(0, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (, uint256 amount, uint256 total) = _stakeEvent(logs, player);
        assertEq(coin.balanceOf(player), 100, "only the principal leaves the wallet");
        assertEq(total, _whole(total), "the stake is whole FLIP");
        assertGe(amount, 100, "the normalized principal (plus any quest bonus) is staked");
        bytes32 depositSig = keccak256("CoinflipDeposit(uint32,uint256)");
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip) && logs[i].topics[0] == depositSig) {
                assertEq(abi.decode(logs[i].data, (uint256)), 100, "CoinflipDeposit reports the funded principal");
                seen = true;
            }
        }
        assertTrue(seen, "CoinflipDeposit emitted");
        assertEq(coinflip.coinflipAmount(player), total);

        vm.prank(player);
        vm.expectRevert(Coinflip.AmountLTMin.selector);
        coinflip.depositCoinflip(0, 99);
    }

    function test_SelfDepositOverTheCapRevertsAndRollsBack() public {
        _credit(player, CAP - 100_000);
        _mint(player, 200_000);
        vm.prank(player);
        coinflip.depositCoinflip(0, 100);
        uint256 stake = coinflip.coinflipAmount(player);
        assertGe(stake, CAP - 100_000 + 100, "a deposit inside the cap is accepted");
        uint256 wallet = coin.balanceOf(player);

        vm.prank(player);
        vm.expectRevert(Coinflip.StakeAboveDailyCap.selector);
        coinflip.depositCoinflip(0, 100_000);
        assertEq(coin.balanceOf(player), wallet, "the burn rolled back");
        assertEq(coinflip.coinflipAmount(player), stake, "nothing was added");
    }

    function test_RecycleBonusPushingOverTheCapRevertsAndRestoresTheBank() public {
        // Bank a win: the payout is whole FLIP, its 0.75% recycle bonus is what overflows.
        uint256 stake = 10_000;
        _mint(player, stake);
        vm.prank(operator);
        coinflip.depositCoinflip(playerId, stake);
        _resolveDay(3, true);
        uint256 payout = coinflip.previewClaimCoinflips(player);
        assertGt(payout, 0, "fixture: a banked win");
        _warpToDay(3);

        // Fill tomorrow's lane so principal fits but principal + bonus does not.
        uint256 fill = CAP - payout - UNIT;
        _mint(gifter, fill);
        vm.prank(gifter);
        coinflip.depositCoinflip(playerId, fill);
        assertEq(coinflip.coinflipAmount(player), fill);

        vm.prank(player);
        vm.expectRevert(Coinflip.StakeAboveDailyCap.selector);
        coinflip.depositCoinflip(0, payout);
        assertEq(coinflip.previewClaimCoinflips(player), payout, "the claimable draw rolled back with the revert");
        assertEq(coinflip.coinflipAmount(player), fill, "nothing was added");
    }

    function test_OperatorAndGiftDepositsOverTheCapRevert() public {
        _credit(player, CAP - 50);
        _mint(player, 100);
        _mint(gifter, 100);

        vm.prank(operator);
        vm.expectRevert(Coinflip.StakeAboveDailyCap.selector);
        coinflip.depositCoinflip(playerId, 100);

        vm.prank(gifter);
        vm.expectRevert(Coinflip.StakeAboveDailyCap.selector);
        coinflip.depositCoinflip(playerId, 100);

        assertEq(coin.balanceOf(player), 100);
        assertEq(coin.balanceOf(gifter), 100);
    }

    function test_GiftDepositBelowMinimumIsRejected() public {
        _mint(gifter, 100);
        vm.prank(gifter);
        vm.expectRevert(Coinflip.AmountLTMin.selector);
        coinflip.depositCoinflip(playerId, 100 - 1);
    }

    // =====================================================================
    //                 4. SEEDS and sDGNRS backing
    // =====================================================================

    function test_ConstructorSeedWritesNoLane() public view {
        for (uint24 d; d <= 24; ++d) {
            assertEq(_rawStake(d, VAULT), 0, "the deploy seed is not stored in a vault lane");
            assertEq(_rawStake(d, SDGNRS), 0, "the deploy seed is not stored in an sDGNRS lane");
        }
        assertEq(coinflip.coinflipAmount(VAULT), SEED, "the deploy window seeds day 3");
        assertEq(coinflip.coinflipAmount(SDGNRS), SEED);
    }

    function test_CenturySeedRidesOnTopOfTheLaneWithoutWritingIt() public {
        _warpToDay(40);
        uint24 first = _targetDay();
        // sDGNRS already holds a stake on the window's first day.
        _credit(SDGNRS, 5_000);
        vm.recordLogs();
        vm.prank(GAME);
        coinflip.armCenturySeed(100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != STAKE_SIG, "arming emits no stake event");
        }
        assertEq(_rawStake(first, SDGNRS), 5_000, "the lane keeps its stored stake only");
        for (uint24 i; i < 20; ++i) {
            assertEq(_rawStake(first + i, VAULT), 0, "no vault lane written");
        }
        assertEq(coinflip.coinflipAmount(SDGNRS), 5_000 + SEED, "the seed adds to the lane");
        assertEq(coinflip.coinflipAmount(VAULT), SEED);

        // A lane at the cap never stalls the arm: arming writes no lane, and the seed rides on top
        // of the clamped lane.
        _credit(SDGNRS, type(uint128).max);
        assertEq(_rawStake(first, SDGNRS), CAP);
        vm.prank(GAME);
        coinflip.armCenturySeed(200);
        assertEq(_rawStake(first, SDGNRS), CAP, "the stored lane stays at its cap, nothing spilled");
        assertEq(coinflip.coinflipAmount(SDGNRS), CAP + SEED, "the seed is held outside the lane");
    }

    function test_SdgnrsBackingMatchesTheWholeTransfer() public {
        // Day 3 is a deploy-window day: the view carries the seed, the lane and its event do not.
        uint256 before = coinflip.coinflipAmount(SDGNRS);
        assertEq(before, SEED);
        vm.recordLogs();
        vm.prank(COIN);
        coinflip.creditSdgnrsBacking(100);
        (, uint256 amount, uint256 total) = _stakeEvent(vm.getRecordedLogs(), SDGNRS);
        assertEq(amount, 100);
        assertEq(total, 100, "the event reports the stored lane");
        assertEq(coinflip.coinflipAmount(SDGNRS), before + 100);

        // A real transfer into sDGNRS: FLIP removes the full amount from supply.
        _mint(player, 50);
        uint256 supply = coin.totalSupply();
        uint256 stake = coinflip.coinflipAmount(SDGNRS);
        vm.prank(player);
        coin.transfer(SDGNRS, 50);
        assertEq(supply - coin.totalSupply(), 50, "the whole transfer left circulation");
        assertEq(coinflip.coinflipAmount(SDGNRS) - stake, 50, "the full transfer becomes stake");

        // Backing at the cap saturates without reverting FLIP's transfer path.
        _credit(SDGNRS, CAP);
        vm.prank(COIN);
        coinflip.creditSdgnrsBacking(1);
        assertEq(_rawStake(_targetDay(), SDGNRS), CAP, "the stored lane saturates");
        assertEq(coinflip.coinflipAmount(SDGNRS), CAP + SEED, "the seed rides on top of the saturated lane");
    }

    // =====================================================================
    //                 5. Preview/claim agree on packed stakes
    // =====================================================================

    function test_PreviewMatchesClaimAndClearedLanesCannotReplay() public {
        _mint(player, 1_000);
        vm.prank(player);
        coinflip.depositCoinflip(0, 1_000);
        uint256 stakeDay3 = coinflip.coinflipAmount(player);
        _resolveDay(3, true);
        (uint16 r,) = coinflip.getCoinflipDayResult(3);
        uint256 payout = stakeDay3 + (stakeDay3 * uint256(r)) / 100;
        assertEq(coinflip.previewClaimCoinflips(player), payout);
        vm.prank(player);
        assertEq(coinflip.claimCoinflips(0, type(uint256).max), payout, "claim pays the preview");
        assertEq(_rawStake(3, player), 0, "the lane is cleared");
        vm.prank(player);
        assertEq(coinflip.claimCoinflips(0, type(uint256).max), 0, "no replay");
    }

    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 word = uint256(keccak256(abi.encodePacked("packed_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }
}
