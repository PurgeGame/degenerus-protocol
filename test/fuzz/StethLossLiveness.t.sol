// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev Etched over the Game only to seed an outstanding claimable and loan collateral; the real runtime
///      is restored straight after. Backing ETH is dealt to the Game by the caller.
contract StethLossSeeder is DegenerusGameStorage {
    function seedLevel(uint32 id, uint24 lvl, uint32 entries) external { _queueEntries(id, lvl, entries, false); }

    function credit(uint32 id, uint256 amount) external {
        _creditClaimable(id, amount);
        claimablePool += uint128(amount);
    }
}

/// @title StethLossLiveness -- an stETH loss may cost money, it must never brick the game.
/// @notice LIVENESS / BRICK test, NOT an accounting test. The Game keeps part of its backing as stETH
///         (the vault owner stakes ETH via `adminStakeEthForStEth`, and the mock stands in for Lido).
///         This suite plays a running game with every kind of open obligation at once, cuts the Game's
///         stETH balance by a fraction (10%, 50%, 100% and a fuzzed fraction), and then asserts only that
///         the catastrophic failure modes never happen:
///           - `mineFlip` keeps making progress (the daily cycle completes with the VRF word fulfilled
///             through the mock coordinator) and refuses only with its two benign signals
///             (`NoWork`, `RngNotReady`), never a panic or any other revert,
///           - level transitions still occur when targets are met, including the seizure of an overdue
///             loan,
///           - game over (liveness timeout) latches and the terminal payouts complete,
///           - every claim either pays or reverts with the documented shortfall error
///             (`TransferFailed`, an ETH/stETH payout that the balance cannot cover) and never with a
///             panic, and a shortfall claim can always take the ETH that exists via the partial form,
///           - the final sweep (30 days after game over) completes and leaves the Game empty.
///         A SHORTFALL ITSELF IS ACCEPTABLE: after a loss, claimants may be paid less than they are
///         owed or be unable to take the full claim. Nothing here checks who is owed what.
contract StethLossLiveness is RedemptionFixture {
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 private constant TRANSFER_FAILED = bytes4(keccak256("TransferFailed()"));
    bytes4 private constant PANIC = 0x4e487b71;

    address private constant DEAD = address(0xdead);

    address private keeper = makeAddr("keeper");
    address private driver = makeAddr("driver");
    address private borrower = makeAddr("borrower");
    address private subscriber = makeAddr("subscriber");
    address private bystander = makeAddr("bystander");

    DegenerusGameLens private lens;
    uint32 private borrowerId;
    uint32 private subscriberId;
    uint32 private bystanderId;
    uint24 private loanDue;
    uint32 private redemptionBatch;
    uint256 private cranks;
    uint256 private answeredWords;

    function setUp() public override {
        super.setUp();
        lens = new DegenerusGameLens();
        vm.deal(keeper, 1 ether);
        vm.deal(driver, 1_000_000 ether);
    }

    // ---------------------------------------------------------------- scenarios

    /// @dev When the loss lands: mid-game (obligations are then re-priced by the terminal drain), right after
    ///      the game-over latch (terminal credits were granted while the stETH still existed, so claimants
    ///      meet a real shortfall), or after the claims and before the final sweep (the sweep's pro-rata leg).
    uint8 private constant MID_GAME = 0;
    uint8 private constant AFTER_GAME_OVER = 1;
    uint8 private constant BEFORE_SWEEP = 2;

    uint256 private shortfalls;
    uint256 private paidClaims;

    function test_stethLoss10Percent_midGame() public { _scenario(1_000, MID_GAME); }

    function test_stethLoss50Percent_midGame() public { _scenario(5_000, MID_GAME); }

    function test_stethLoss100Percent_midGame() public { _scenario(10_000, MID_GAME); }

    function test_stethLoss10Percent_afterGameOver() public { _scenario(1_000, AFTER_GAME_OVER); }

    function test_stethLoss50Percent_afterGameOver() public { _scenario(5_000, AFTER_GAME_OVER); }

    function test_stethLoss100Percent_afterGameOver() public {
        _scenario(10_000, AFTER_GAME_OVER);
        assertGt(shortfalls, 0, "a total loss after the terminal credits must surface a claim shortfall");
    }

    function test_stethLoss10Percent_beforeSweep() public { _scenario(1_000, BEFORE_SWEEP); }

    function test_stethLoss50Percent_beforeSweep() public { _scenario(5_000, BEFORE_SWEEP); }

    function test_stethLoss100Percent_beforeSweep() public { _scenario(10_000, BEFORE_SWEEP); }

    /// forge-config: default.fuzz.runs = 24
    function testFuzz_stethLossAnyFractionAnyTime(uint256 bps, uint8 when) public {
        _scenario(bound(bps, 1, 10_000), uint8(bound(when, 0, 2)));
    }

    function _scenario(uint256 lossBps, uint8 when) private {
        _buildRunningGame();
        assertGt(mockStETH.balanceOf(address(game)), 0, "fixture: the Game must hold stETH");
        uint24 levelBefore = game.level();

        if (when == MID_GAME) _cutStETH(lossBps);

        // 1. The daily cycle and level transitions keep running: more levels are reached, and the
        //    overdue loan is seized on the way through its due level.
        uint256 crankedBefore = cranks;
        uint256 wordsBefore = answeredWords;
        _playUntilLevel(levelBefore + 3, 90);
        assertGt(answeredWords, wordsBefore, "no VRF word was fulfilled through the daily cycle");
        assertGe(game.level(), levelBefore + 3, "level transitions stalled");
        assertGt(cranks, crankedBefore, "mineFlip made no progress");
        assertGe(game.level(), loanDue, "the scenario never reached the loan's due level");
        assertEq(lens.loanOf(address(game), borrowerId).principal, 0, "the due loan was neither repaid nor seized");

        // 2. Game over by liveness timeout; the terminal payouts complete.
        _driveToGameOver();
        assertTrue(game.gameOver(), "game over never latched");
        if (when == AFTER_GAME_OVER) _cutStETH(lossBps);

        // 3. Claims pay or revert with the documented shortfall error, never a panic.
        _claimAll();
        if (when == BEFORE_SWEEP) _cutStETH(lossBps);

        // 4. The final sweep, 30 days after game over, completes and empties the Game.
        vm.warp(vm.getBlockTimestamp() + 30 days + 1);
        _crank(40);
        assertEq(address(game).balance, 0, "the final sweep left ETH in the Game");
        assertLe(mockStETH.balanceOf(address(game)), 2, "the final sweep left stETH in the Game");
    }

    /// @dev The loss: stETH leaves the Game, ETH-denominated obligations stay.
    function _cutStETH(uint256 lossBps) private {
        uint256 held = mockStETH.balanceOf(address(game));
        vm.prank(address(game));
        mockStETH.transfer(DEAD, held * lossBps / 10_000);
        if (lossBps == 10_000) assertLe(mockStETH.balanceOf(address(game)), 2, "fixture: total loss");
    }

    // ---------------------------------------------------------------- the running game

    /// @dev Real play (a funded driver buys tickets plus a 60 ETH lootbox per day), then every open
    ///      obligation at once: stETH held by the Game, player claimable, an open loan that falls due
    ///      two levels on, an AFKing subscription and a pending sDGNRS redemption batch.
    function _buildRunningGame() private {
        _playUntilLevel(3, 40);
        assertGe(game.level(), 3, "fixture: the game must be mid-run");

        // Outstanding player claimable: the driver's real jackpot wins, plus a bystander who holds
        // only a credit. The credit is ETH-backed at the Game (obligations stay covered).
        bystanderId = _giveWalletId(bystander);
        _seeder(bystanderId, 0, 0, 25 ether, 0);

        // An open loan: the borrower holds far-future tickets; the sDGNRS account lends.
        borrowerId = _giveWalletId(borrower);
        loanDue = game.level() + 2;
        _seeder(borrowerId, uint24(loanDue + 4), 600, 0, 0);
        _seeder(SDGNRS_ID, 0, 0, 100 ether, 0);
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), borrowerId, loanDue, type(uint256).max);
        assertTrue(q.eligible, "fixture: the loan must be borrowable");
        assertGt(q.principal, 0, "fixture: the loan must have a principal");
        _idle();
        vm.prank(borrower);
        game.borrow(borrowerId, loanDue, type(uint256).max, 0);
        assertTrue(lens.loanOf(address(game), borrowerId).principal != 0, "fixture: loan is open");

        // An AFKing subscription with prepaid funds.
        uint256 seat = _grantSeat(subscriber);
        subscriberId = _giveWalletId(subscriber);
        vm.deal(subscriber, 10 ether);
        _idle();
        vm.prank(subscriber);
        game.depositAfkingFunding{value: 2 ether}(subscriberId);
        vm.prank(subscriber);
        game.subscribe(0, true, 1, seat);

        // A pending sDGNRS redemption batch: alice burns, the batch stays open.
        redemptionBatch = _openBatchId();
        _burn(alice, _minimumLiveBurn());
        assertGt(_claimTokens(alice, redemptionBatch), 0, "fixture: alice has a pending redemption");
        assertGt(game.claimableWinningsOf(bystander), 1, "fixture: outstanding player claimable");
        assertGt(game.subscriberSetLength(), 2, "fixture: an AFKing subscription beyond the two protocol ones");

        // The Game holds a large part of its backing as stETH: the daily auto-stake moves everything above the
        // claimable reserve into Lido. Top up with the vault owner's manual stake when ETH is free.
        uint256 reserve = game.claimablePoolView();
        uint256 free = address(game).balance > reserve ? address(game).balance - reserve : 0;
        if (free > 1 ether) {
            vm.prank(_vaultOwner());
            game.adminStakeEthForStEth(free * 8 / 10);
        }
        assertGt(mockStETH.balanceOf(address(game)), 20 ether, "fixture: the Game must hold real stETH");
    }

    function _vaultOwner() private view returns (address) {
        return ContractAddresses.OWNER_GOVERNANCE;
    }

    uint32 private constant SDGNRS_ID = 2;

    /// @dev Seed collateral entries at `lvl` (if `entries != 0`) and a backed claimable credit.
    function _seeder(uint32 id, uint24 lvl, uint32 entries, uint256 claimable, uint256) private {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(StethLossSeeder).runtimeCode);
        if (entries != 0) StethLossSeeder(address(game)).seedLevel(id, lvl, entries);
        if (claimable != 0) StethLossSeeder(address(game)).credit(id, claimable);
        vm.etch(address(game), real);
        if (claimable != 0) vm.deal(address(game), address(game).balance + claimable);
    }

    // ---------------------------------------------------------------- driving

    function _playUntilLevel(uint24 target, uint256 maxDays) private {
        for (uint256 day; day < maxDays && game.level() < target && !game.gameOver(); ++day) {
            vm.warp(vm.getBlockTimestamp() + 1 days + 1);
            (, , , bool locked, uint256 priceWei) = game.purchaseInfo();
            if (!locked) {
                uint256 box = 60 ether;
                vm.prank(driver);
                try game.purchase{value: priceWei * 10 + box}(
                    0, 4000, BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false
                ) {} catch {}
            }
            _crank(120);
        }
    }

    /// @dev Latch game over through the liveness timeout and the real crank.
    function _driveToGameOver() private {
        vm.warp(vm.getBlockTimestamp() + 370 days);
        for (uint256 i; i < 400 && !game.gameOver(); ++i) _crank(8);
    }

    function _idle() private { _crank(200); }

    /// @dev Crank `mineFlip`, answering every VRF request through the mock coordinator. Stops when the
    ///      engine reports no work. Any revert other than the two benign signals fails the test: a
    ///      panic or a stuck stage after an stETH loss is the brick this suite exists to catch.
    function _crank(uint256 maxCalls) private {
        for (uint256 i; i < maxCalls; ++i) {
            bool answered = _fulfillPending(uint256(keccak256(abi.encode("stlive", cranks, i))) | 1);
            if (answered) ++answeredWords;
            vm.prank(keeper);
            try game.mineFlip(0) {
                ++cranks;
            } catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (sel == PANIC) fail("mineFlip PANICKED after an stETH loss");
                else if (sel == NO_WORK) return;
                else if (sel == RNG_NOT_READY) {
                    if (answered) continue;
                    if (!_fulfillPending(uint256(keccak256(abi.encode("stlive-retry", cranks, i))) | 1)) return;
                    ++answeredWords;
                } else {
                    emit log_named_bytes("unexpected mineFlip revert", reason);
                    fail("mineFlip reverted with an unexpected error after an stETH loss");
                }
            }
        }
    }

    // ---------------------------------------------------------------- claims

    function _claimAll() private {
        address[6] memory who = [driver, borrower, subscriber, bystander, address(sdgnrs), ContractAddresses.CREATOR];
        for (uint256 i; i < who.length; ++i) {
            uint256 owed = game.claimableWinningsOf(who[i]);
            vm.prank(who[i]);
            try game.claimWinnings(0) {
                ++paidClaims;
            } catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                assertTrue(sel != PANIC, "a claim PANICKED after an stETH loss");
                // The documented shortfall error. NothingToClaim is an empty balance, not a shortfall.
                if (sel != TRANSFER_FAILED && sel != bytes4(keccak256("NothingToClaim()"))) {
                    emit log_named_bytes("unexpected claim revert", reason);
                    fail("a claim reverted with something other than the shortfall error");
                }
                // The ETH that exists is always takeable by the partial form.
                uint256 ethOnHand = address(game).balance;
                if (sel == TRANSFER_FAILED) ++shortfalls;
                if (sel == TRANSFER_FAILED && owed > 1 && ethOnHand != 0) {
                    uint256 cap = ethOnHand < owed - 1 ? ethOnHand : owed - 1;
                    vm.prank(who[i]);
                    try game.claimWinnings(0, cap) {} catch (bytes memory r2) {
                        // An afking bucket merged into the payout can push it past the ETH on hand;
                        // that is still the shortfall error, never a panic.
                        assertTrue(bytes4(r2) == TRANSFER_FAILED, "partial claim reverted with a non-shortfall error");
                    }
                }
            }
        }
        // The pending redemption batch: settled by the miner during the run (nothing left to claim), or
        // still claimable at the terminal value, paid from sDGNRS's own holdings.
        uint256 pending = _claimTokens(alice, redemptionBatch);
        emit log_named_uint("redemption roll", _rollOf(redemptionBatch));
        emit log_named_uint("redemption pending tokens", pending);
        if (pending != 0) {
            vm.prank(alice);
            try sdgnrs.claimRedemption(0, redemptionBatch) {}
            catch (bytes memory reason) {
                assertTrue(bytes4(reason) != PANIC, "a redemption claim PANICKED after an stETH loss");
                emit log_named_bytes("redemption claim reverted", reason);
            }
            assertEq(_claimTokens(alice, redemptionBatch), 0, "the redemption claim did not settle");
        }
    }
}
