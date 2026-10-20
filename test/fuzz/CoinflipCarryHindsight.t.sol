// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipCarryHindsight — a dormant auto-rebuy account gets no look-ahead on its carry
/// @notice Every claim walk settles through flipsClaimableDay in one call: the 90-day claim
///         window bounds auto-rebuy walks too, so days older than the window forfeit instead of
///         staying queued behind the cursor. A carry therefore never moves while a resolved
///         day it rides is still unapplied. Each route below pairs a dormant account with a
///         caught-up control holding the same stake and results; both get exactly the same,
///         0 around a known loss:
///         1. CARRY CLAIM  — claimCoinflipCarry after a long dormancy (self-funded and credit).
///         2. EXIT         — setCoinflipAutoRebuy(false) after a two-window dormancy.
///         3. TAKE-PROFIT  — the setter with T = 1 and with T = the run-peak payout of a known
///                           win run, self-funded and credit-staked.
///         4. FORFEIT      — a backlog longer than 90 days drops the days before the window
///                           and the carry that would have ridden them, and the preview
///                           agrees with the settle.
/// @dev The real deployed protocol (DeployProtocol). Days resolve through the GAME's own
///      `processCoinflipPayouts(bonus, word, day)` with the wall clock on that day, as the daily
///      advance does; word parity is forced only on the key days. FLIP funding uses
///      `mintForGame` as GAME and credits use `creditFlip` as GAME, the routes every ordinary
///      award takes. No storage writes; lastClaim is read with vm.load and cross-checked against
///      the public startDay getter.
contract CoinflipCarryHindsight is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    uint24 internal constant ARM_DAY = 2;
    uint24 internal constant WINDOW = 90; // Coinflip.COIN_CLAIM_DAYS
    uint256 internal constant STAKE = 100_000; // whole FLIP

    address internal dormant;
    address internal control;
    uint32 internal dormantId;
    uint32 internal controlId;
    uint24 internal lastResolved;

    function setUp() public {
        _deployProtocol();
        dormant = makeAddr("hindsight_dormant");
        control = makeAddr("hindsight_control");
        _resolveDay(ARM_DAY, false);
        // Arming self-registers both accounts; take-profit 0, no stake.
        vm.prank(dormant);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        vm.prank(control);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        dormantId = game.walletIdOf(dormant);
        controlId = game.walletIdOf(control);
        assertTrue(dormantId != 0 && controlId != 0, "arming registered both accounts");
        assertEq(_lastClaim(dormantId), ARM_DAY);
        assertEq(_lastClaim(controlId), ARM_DAY);
    }

    // ------------------------------------------------------------------ helpers

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    function _word(uint24 epoch) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("carry_hindsight_word", epoch)));
    }

    function _resolveDay(uint24 epoch, bool win) internal {
        _warpToDay(epoch);
        uint256 w = _word(epoch);
        w = win ? (w | 1) : (w & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, w, epoch);
        lastResolved = epoch;
    }

    /// @dev Filler days [from, to] with their natural word parity.
    function _resolveRange(uint24 from, uint24 to) internal {
        for (uint24 d = from; d <= to; ++d) {
            _warpToDay(d);
            vm.prank(GAME);
            coinflip.processCoinflipPayouts(0, _word(d), d);
        }
        lastResolved = to;
    }

    /// @dev Days [from, to] all forced to win.
    function _resolveWins(uint24 from, uint24 to) internal {
        for (uint24 d = from; d <= to; ++d) _resolveDay(d, true);
    }

    function _lastClaim(uint32 id) internal view returns (uint24) {
        uint256 w0 = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint256(id), uint256(2)))));
        (, , , uint24 startDay) = coinflip.coinflipAutoRebuyInfoById(id);
        require(uint24(w0 >> 152) == startDay, "slot decode mismatch");
        return uint24(w0 >> 128);
    }

    function _carryOf(uint32 id) internal view returns (uint256 carry) {
        (, , carry, ) = coinflip.coinflipAutoRebuyInfoById(id);
    }

    function _payout(uint256 stake, uint24 epoch) internal view returns (uint256) {
        (uint16 r, bool win) = coinflip.getCoinflipDayResult(epoch);
        require(win, "not a win");
        return stake + (stake * uint256(r)) / 100;
    }

    /// @dev Carry after a take-profit-0 win (recycle bonus included).
    function _roll(uint256 payout) internal pure returns (uint256) {
        return payout + (payout * 75) / 10_000;
    }

    function _fund(address who, uint256 amt) internal {
        vm.prank(GAME);
        coin.mintForGame(who, amt);
    }

    function _credit(uint32 id) internal {
        vm.prank(GAME);
        coinflip.creditFlip(id, STAKE);
    }

    /// @dev The account's walk reached the resolved frontier.
    function _assertCurrent(uint32 id, string memory label) internal {
        assertTrue(coinflip.flipResolvedToday(), "today applied: the carry gates are open");
        assertEq(_lastClaim(id), lastResolved, label);
    }

    // ------------------------------------------------------------------ 1. carry claim

    /// Self-funded write-up path: armed on 2, deposit on 91 (89 days dormant), the stake rides
    /// 92 (WIN), 93 LOSS, claimCoinflipCarry on 93. The deposit's walk already reaches 91,
    /// and the claim walks 92..93 first, so the loss zeroes the carry for both accounts.
    function test_DormantCarryClaimGetsNothingAroundSettledLoss() public {
        _resolveRange(ARM_DAY + 1, 46);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _assertCurrent(controlId, "control current mid-way");
        _resolveRange(47, 91);

        _fund(dormant, STAKE);
        _fund(control, STAKE);
        vm.prank(dormant);
        coinflip.depositCoinflip(0, STAKE);
        vm.prank(control);
        coinflip.depositCoinflip(0, STAKE);
        _assertCurrent(dormantId, "one deposit walk settles the whole 89-day backlog");
        _assertCurrent(controlId, "control current");
        assertEq(coinflip.coinflipAmountById(dormantId), coinflip.coinflipAmountById(controlId), "equal stakes");

        _resolveDay(92, true);
        _resolveDay(93, false);

        vm.prank(dormant);
        uint256 d = coinflip.claimCoinflipCarry(0, type(uint256).max);
        vm.prank(control);
        uint256 c = coinflip.claimCoinflipCarry(0, type(uint256).max);
        _assertCurrent(dormantId, "the carry claim settled through 93 first");
        assertEq(d, 0, "dormant: the known 93 loss zeroed the carry");
        assertEq(c, 0, "control: the known 93 loss zeroed the carry");
        assertEq(_carryOf(dormantId), 0);
        assertEq(coin.balanceOf(dormant), coin.balanceOf(control), "dormant ends where the control does");
    }

    /// The other branch: 93 WINS. The dormant account cannot walk part-way and pick its moment;
    /// one claim settles both days and pays the same compounded carry the control gets.
    function test_DormantKnownWinPaysExactlyTheControl() public {
        _resolveRange(ARM_DAY + 1, 91);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _fund(dormant, STAKE);
        _fund(control, STAKE);
        vm.prank(dormant);
        coinflip.depositCoinflip(0, STAKE);
        vm.prank(control);
        coinflip.depositCoinflip(0, STAKE);
        _resolveDay(92, true);
        _resolveDay(93, true);

        vm.prank(dormant);
        coinflip.claimCoinflips(0, 0);
        _assertCurrent(dormantId, "a settle-only call walks through 93, not to a chosen day");
        uint256 expected = _roll(_payout(_roll(_payout(STAKE, 92)), 93));
        vm.prank(dormant);
        uint256 d = coinflip.claimCoinflipCarry(0, type(uint256).max);
        vm.prank(control);
        uint256 c = coinflip.claimCoinflipCarry(0, type(uint256).max);
        assertEq(d, expected, "dormant gets the settled carry");
        assertEq(c, d, "and exactly what the control gets");
    }

    /// Credit route on the window boundary: a credit on 92 (90 days after the cursor) rides
    /// 93 (WIN), 94 LOSS. The walk clamps to 94 - 90 and settles through 94.
    function test_CreditRouteAtWindowBoundaryGetsNothing() public {
        _resolveRange(ARM_DAY + 1, 92);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _credit(dormantId);
        _credit(controlId);
        assertEq(_lastClaim(dormantId), ARM_DAY, "the credit did not walk the account");
        _resolveDay(93, true);
        _resolveDay(94, false);

        vm.prank(dormant);
        uint256 d = coinflip.claimCoinflipCarry(0, type(uint256).max);
        vm.prank(control);
        uint256 c = coinflip.claimCoinflipCarry(0, type(uint256).max);
        _assertCurrent(dormantId, "one walk reaches 94");
        assertEq(d, 0, "dormant: carry lost on 94");
        assertEq(c, 0, "control: carry lost on 94");
        assertEq(coin.balanceOf(dormant), 0);
    }

    // ------------------------------------------------------------------ 2. rebuy exit

    /// Two windows of dormancy: a credit on 181 rides 182 (WIN), 183 LOSS; the exit settles
    /// through 183 before releasing anything, so it mints 0 and turns rebuy off.
    function test_ExitAfterTwoWindowsReleasesNothingAroundSettledLoss() public {
        _resolveRange(ARM_DAY + 1, 181);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _credit(dormantId);
        _credit(controlId);
        _resolveDay(182, true);
        _resolveDay(183, false);

        vm.prank(dormant);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        vm.prank(control);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        (bool dEnabled, , , ) = coinflip.coinflipAutoRebuyInfoById(dormantId);
        assertFalse(dEnabled, "rebuy off");
        _assertCurrent(dormantId, "the exit walk settled through 183");
        assertEq(coin.balanceOf(dormant), 0, "dormant exit: the 183 loss zeroed the carry");
        assertEq(coin.balanceOf(control), 0, "control exit: same");
    }

    // ------------------------------------------------------------------ 3. take-profit

    /// Credit on 47 rides 48 (WIN), 49 LOSS. Setting take-profit 1 settles 48/49 under the
    /// old value first, so the known win is never re-split into the bank.
    function test_TakeProfitOneCannotResplitKnownWin() public {
        _resolveRange(ARM_DAY + 1, 47);
        _credit(dormantId);
        _credit(controlId);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _resolveDay(48, true);
        _resolveDay(49, false);

        vm.prank(dormant);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, 1);
        vm.prank(control);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, 1);
        _assertCurrent(dormantId, "the setter settled 48/49 under the old value");

        vm.prank(dormant);
        uint256 d = coinflip.claimCoinflips(0, type(uint256).max);
        vm.prank(control);
        uint256 c = coinflip.claimCoinflips(0, type(uint256).max);
        assertEq(d, 0, "dormant: the 48 win rode into the 49 loss");
        assertEq(c, 0, "control: same");
    }

    /// Run-peak route, self-funded with 90 days of dormancy: the stake rides 93; 93/94/95
    /// WIN, 96 LOSS, all public. A threshold equal to the 95 payout cannot bank the known
    /// peak: the setter settles 93..96 under take-profit 0 first.
    function test_RunPeakTakeProfitSelfFundedGetsNothing() public {
        _resolveRange(ARM_DAY + 1, 47);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _resolveRange(48, 92);
        _fund(dormant, STAKE);
        _fund(control, STAKE);
        vm.prank(dormant);
        coinflip.depositCoinflip(0, STAKE);
        vm.prank(control);
        coinflip.depositCoinflip(0, STAKE);
        _assertCurrent(dormantId, "the deposit walk settled the 90-day backlog");

        _resolveDay(93, true);
        _resolveDay(94, true);
        _resolveDay(95, true);
        _resolveDay(96, false);
        uint256 p95 = _payout(_roll(_payout(_roll(_payout(STAKE, 93)), 94)), 95);

        vm.prank(dormant);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, p95);
        vm.prank(control);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, p95);
        _assertCurrent(dormantId, "the threshold is stored only after 96 settles");

        vm.prank(dormant);
        uint256 d = coinflip.claimCoinflips(0, type(uint256).max);
        vm.prank(control);
        uint256 c = coinflip.claimCoinflips(0, type(uint256).max);
        assertEq(d, 0, "dormant: the run rode into the known 96 loss");
        assertEq(c, 0, "control: same");
        assertEq(_carryOf(dormantId), 0);
    }

    /// Run-peak route, credit-staked: a credit on 48 rides 49; 49/50 WIN, 51 LOSS; the
    /// threshold is the 50 payout.
    function test_RunPeakTakeProfitCreditGetsNothing() public {
        _resolveRange(ARM_DAY + 1, 48);
        _credit(dormantId);
        _credit(controlId);
        vm.prank(control);
        coinflip.depositCoinflip(0, 0);
        _resolveDay(49, true);
        _resolveDay(50, true);
        _resolveDay(51, false);
        uint256 p50 = _payout(_roll(_payout(STAKE, 49)), 50);

        vm.prank(dormant);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, p50);
        vm.prank(control);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, p50);
        _assertCurrent(dormantId, "the setter settled through 51");
        vm.prank(dormant);
        uint256 d = coinflip.claimCoinflips(0, type(uint256).max);
        vm.prank(control);
        uint256 c = coinflip.claimCoinflips(0, type(uint256).max);
        assertEq(d, 0, "dormant: no banked run peak");
        assertEq(c, 0, "control: same");
    }

    // ------------------------------------------------------------------ 4. forfeit past the window

    /// A rebuy-off stake on day 3 (credited on 2) wins. Claimed with day 3 still inside the
    /// window it pays; one day later it has left the window and forfeits.
    function test_StakeOlderThanWindowForfeits() public {
        address plain = makeAddr("hindsight_plain");
        uint32 plainId = _giveWalletId(plain);
        vm.prank(GAME);
        coinflip.creditFlip(plainId, STAKE);
        _resolveDay(3, true);
        uint256 p3 = _payout(STAKE, 3);
        _resolveRange(4, 2 + WINDOW);

        uint256 snap = vm.snapshotState();
        uint256 preview = coinflip.previewClaimCoinflipsById(plainId);
        vm.prank(plain);
        uint256 inside = coinflip.claimCoinflips(0, type(uint256).max);
        assertEq(inside, p3, "day 3 is the window's oldest day and still pays");
        assertEq(preview, inside, "preview == settle");
        vm.revertToState(snap);

        _resolveRange(3 + WINDOW, 3 + WINDOW);
        preview = coinflip.previewClaimCoinflipsById(plainId);
        vm.prank(plain);
        uint256 outside = coinflip.claimCoinflips(0, type(uint256).max);
        _assertCurrent(plainId, "one walk reaches the frontier");
        assertEq(outside, 0, "day 3 left the window: forfeited");
        assertEq(preview, outside, "preview == settle");
    }

    /// A carry stored at lastClaim 3 rides every later day. With a 90-day backlog it rides the
    /// whole forced-win run and banks above the take-profit; with 91 days its first day has
    /// left the window, so the carry is dropped and nothing is banked.
    function test_CarryOlderThanWindowIsDropped() public {
        // A win pays 1000 * (100 + r) FLIP; 999 leaves a nonzero remainder to roll.
        uint256 takeProfit = 999;
        vm.prank(dormant);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, takeProfit);
        _credit(dormantId);
        _resolveDay(3, true);
        vm.prank(dormant);
        uint256 banked = coinflip.claimCoinflips(0, type(uint256).max);
        assertGt(banked, 0, "the day-3 win banked its whole multiples");
        uint256 carry = _carryOf(dormantId);
        assertGt(carry, 0, "and left a rolling carry");
        assertEq(_lastClaim(dormantId), 3);

        _resolveWins(4, 3 + WINDOW);
        uint256 snap = vm.snapshotState();
        uint256 preview = coinflip.previewFlipBackingById(dormantId);
        vm.prank(dormant);
        uint256 inside = coinflip.claimCoinflips(0, type(uint256).max);
        assertGt(inside, 0, "90-day backlog: the carry rode the run and banked");
        assertEq(preview, inside + _carryOf(dormantId), "preview == settle");
        vm.revertToState(snap);

        _resolveDay(4 + WINDOW, true);
        preview = coinflip.previewFlipBackingById(dormantId);
        vm.prank(dormant);
        uint256 outside = coinflip.claimCoinflips(0, type(uint256).max);
        _assertCurrent(dormantId, "one walk reaches the frontier");
        assertEq(outside, 0, "91-day backlog: the carry is dropped, nothing banks");
        assertEq(_carryOf(dormantId), 0, "carry cleared");
        assertEq(preview, 0, "preview == settle");
        (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfoById(dormantId);
        assertTrue(enabled, "rebuy stays on");
    }
}
