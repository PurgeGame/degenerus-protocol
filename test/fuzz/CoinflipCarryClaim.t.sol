// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CoinflipCore} from "../../contracts/modules/CoinflipCore.sol";

import {DegenesisDeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title CoinflipCarryClaim — partial carry withdrawal while staying on auto-rebuy
/// @notice Proves claimCoinflipCarry:
///         1. PARTIAL  — settles resolved days first (win rolls into carry; the recycle
///                       bonus joins the stake when the carry rides), withdraws
///                       exactly `amount` as minted FLIP, and the remainder keeps riding the next flip.
///         2. CAP      — `amount` above the carry claims the whole carry and leaves
///                       auto-rebuy ENABLED (it is a withdrawal, not an exit).
///         3. ORDER    — a pending loss is settled BEFORE the withdrawal, so a wiped
///                       carry cannot be extracted around the loss.
///         4. GATES    — reverts RngLocked until today's flip is APPLIED (reopening at
///                       settlement, even with the game's RNG lock still up), and
///                       AutoRebuyNotEnabled for a player not on auto-rebuy.
///         5. TAKE-PROFIT — with autoRebuyStop = T, a win banks floor(payout/T)*T
///                       into claimableStored (claimCoinflips territory) and only
///                       the remainder rolls as carry;
///                       claimCoinflipCarry pays from the carry alone.
///         6. GAMEPLAY BURNS — consumeCoinflipsForBurn takes the bank, then a player's
///                       carry only once today's flip is applied; protocol accounts,
///                       transfers and claims never reach it.
contract CoinflipCarryClaim is DegenesisDeployProtocol {
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
        uint256 word = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)),
            bytes32((word & ~(uint256(0xffffff) << 176)) | (uint256(d) << 176)));
        uint256 gameWord = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0),
            bytes32((gameWord & ~(uint256(0xffffff) << 24)) | (uint256(d) << 24)));
        // These fixtures directly settle daily outcomes; keep the independent progress clock current.
        uint256 clocks = uint256(vm.load(address(game), bytes32(GameSlots.LAST_DAILY_COMPLETED_AT)));
        uint256 ts = (uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621;
        vm.store(address(game), bytes32(GameSlots.LAST_DAILY_COMPLETED_AT),
            bytes32((clocks & ~(uint256(type(uint48).max) << 128)) | (ts << 128)));

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
        stake = 100_000;
        vm.prank(GAME);
        coin.mintForGame_g152734(player, stake);
        uint32 playerId = _giveWalletId(player);
        vm.prank(player);
        game.setOperatorApproval(0, operator, true);
        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, true, takeProfit);
        vm.prank(operator);
        coinflip.playCoinflip(playerId, stake);
    }

    /// @dev Win payout for `stake` on day `epoch`; a just-formed carry carries no bonus.
    function _carryAfterWin(uint256 stake, uint24 epoch) internal view returns (uint256) {
        (uint16 r, ) = coinflip.getCoinflipDayResult(epoch);
        return stake + (stake * uint256(r)) / 100;
    }

    /// @dev Carry after a win on `epoch` that `carry` rides: the recycle bonus joins the stake.
    function _carryAfterRide(uint256 carry, uint24 epoch) internal view returns (uint256) {
        return _carryAfterWin(carry + (carry * 75) / 10_000, epoch);
    }

    function test_PartialClaimLeavesRemainderRolling() public {
        uint256 stake = _enterRebuyWithStake();
        _resolveDay(3, true);

        uint256 expectedCarry = _carryAfterWin(stake, 3);
        uint256 take = 50_000;
        uint256 balBefore = coin.balanceOf(player);

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(0, take);

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
        uint256 expectedNext = _carryAfterRide(expectedCarry - take, 4);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0); // settle-only probe (claims nothing)
        (, , uint256 carryNext, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryNext, expectedNext, "remainder kept rolling and compounded");
    }

    function test_FullClaimCapsAtCarryAndStaysOnRebuy() public {
        uint256 stake = _enterRebuyWithStake();
        _resolveDay(3, true);
        uint256 expectedCarry = _carryAfterWin(stake, 3);

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(0, type(uint256).max);

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
        uint256 claimed = coinflip.claimCoinflipCarry(0, type(uint256).max);

        assertEq(claimed, 0, "the loss is settled first - nothing to extract around it");
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry, 0, "carry wiped by the settled loss");
        assertEq(coin.balanceOf(player), 0, "no FLIP escaped the loss");
    }

    function test_TakeProfitBanksReservedChunksAndCarriesRemainder() public {
        // Not a 1000-FLIP multiple, so the payout (always one) can never split
        // evenly into chunks: both the reserved and remainder legs are exercised.
        uint256 takeProfit = 30_001;
        uint256 stake = _enterRebuyWithStake(takeProfit);
        _resolveDay(3, true);

        (uint16 r, ) = coinflip.getCoinflipDayResult(3);
        uint256 payout = stake + (stake * uint256(r)) / 100;
        uint256 reserved = (payout / takeProfit) * takeProfit;
        uint256 remainder = payout - reserved;
        assertGt(reserved, 0, "fixture must bank at least one chunk");
        assertGt(remainder, 0, "fixture must leave a rolling remainder");
        uint256 expectedCarry = remainder;

        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(0, type(uint256).max);

        assertEq(
            claimed,
            expectedCarry,
            "carry claim pays the remainder, never the reserved chunks"
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
        uint256 storedClaimed = coinflip.claimCoinflips(0, type(uint256).max);
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
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        coinflip.claimCoinflipCarry(0, 1);
    }

    /// The other side: day 3's payouts are applied and the lock is STILL held (mineFlip
    /// defers the unlock behind its chunked drains). The carry has resolved through day 3's
    /// word and rides day 4, unrequested, so the withdrawal behaves as it would post-unlock.
    /// The mocked lock is the point: it must not gate this path.
    function test_OpensOnceTodaysFlipResolvedUnderHeldLock() public {
        _enterRebuyWithStake();
        _resolveDay(3, true);

        _lockRng();
        vm.prank(player);
        uint256 claimed = coinflip.claimCoinflipCarry(0, 1);
        vm.clearMockedCalls();

        assertEq(claimed, 1, "settled carry withdraws under a still-held lock");
        assertEq(coin.balanceOf(player), 1, "and mints to the player");
    }

    function _lockRng() internal {
        vm.mockCall(
            GAME,
            abi.encodeWithSelector(IDegenerusGame.rngLocked.selector),
            abi.encode(true)
        );
    }

    // ---------------------------------------------------------------------
    // 6. Gameplay burns: the bank, then the carry once today's flip is applied
    // ---------------------------------------------------------------------

    /// FLIP's `_consumeCoinflipShortfall` carries NO freeze gate. While today's flip is
    /// unapplied, `consumeCoinflipsForBurn` reaches `claimableStored` only — settled days the
    /// pending word cannot reprice. That also rests on an adjacency inside
    /// `_setCoinflipAutoRebuy`: the sole writer of `autoRebuyEnabled = false` drains the carry in
    /// the same block, so the `else if (oldCarry != 0)` branch in `_claimCoinflipsInternal`
    /// (which WOULD fold a carry into `mintable`) is unreachable. Pin it: the position is
    /// frozen, a live carry rides the unapplied day, and a consume for an arbitrary amount must
    /// take the settled bank and leave the carry exactly as it found it.
    function testFuzz_FrozenBurnConsumeNeverReachesTheCarry(uint96 wantRaw) public {
        _enterRebuyWithStake(50_000); // take-profit banks chunks AND leaves a carry
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0); // settle while day 3 is applied
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
        coinflip.claimCoinflipCarry(0, 0);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertGt(carry, 0, "precondition: a carry exists to strand");

        vm.prank(player);
        coinflip.setCoinflipAutoRebuy(0, false, 0);

        (bool enabled, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertFalse(enabled, "position is disabled");
        assertEq(carryAfter, 0, "and holds no carry the burn path could later fold into mintable");
    }

    /// THE requirement, stated whole: nobody can change the carry amount riding the current
    /// day's flip once that day's result becomes knowable. Knowable is the operative word — the
    /// day boundary itself is not the hazard, since no word has been requested there yet. The
    /// carry's writers, driven here while day 4 sits unapplied with a live carry on it (the carry
    /// must be byte-identical at the end) unless noted:
    ///
    ///   _setCoinflipAutoRebuy      -> the exit and the re-arm, both revert here
    ///   claimCoinflipCarry         -> reverts here
    ///   _claimCoinflipsAmount      -> CLAIM_BURN (consumeCoinflipsForBurn) takes the bank only
    ///                                 while frozen; driven below. CLAIM_BACKING
    ///                                 (consumeFlipBacking, withdrawRedeemedFlip) serves GNRUS's
    ///                                 phase-end ticket buy, sDGNRS's Decimator entry and the
    ///                                 sDGNRS redemption close, all made by the Game or sDGNRS
    ///                                 with every requested day applied. Not driven here.
    ///   _claimAcquiredCoinflips    -> gated on !_flipFrozen() like claimCoinflipCarry
    ///   _claimCoinflipsInternal    -> ungated, but its walk stops at flipsClaimableDay, which
    ///                                 by definition of the freeze is strictly before day 4 —
    ///                                 so it can only ever fold ALREADY-public resolved days,
    ///                                 and `lastClaim` makes that idempotent. Driven below.
    function test_NoReachablePathMovesTheCarryRidingAnUnappliedDay() public {
        _enterRebuyWithStake(50_000);
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0); // settle while day 3 is applied
        _warpToDay(4); // day 4 unapplied: its word may be public, the carry rides it

        (, , uint256 carry0, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertGt(carry0, 0, "precondition: a carry is riding the unapplied day");

        // --- gated mutators: every one shut ---
        vm.prank(player);
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(0, false, 0);

        vm.prank(player);
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        coinflip.setCoinflipAutoRebuy(0, true, 1);

        vm.prank(player);
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, 1);

        vm.prank(player);
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        coinflip.claimCoinflipCarry(0, type(uint256).max);

        // --- ungated settle paths: open, and provably carry-neutral ---
        vm.prank(player);
        coinflip.claimCoinflips(0, type(uint256).max);
        vm.prank(ContractAddresses.COIN);
        coinflip.consumeCoinflipsForBurn(player, type(uint256).max);
        vm.prank(ContractAddresses.COIN);
        coinflip.claimCoinflipsFromFlip(player, type(uint256).max);

        // --- a fresh deposit rides TOMORROW, never the unapplied day ---
        vm.prank(GAME);
        coin.mintForGame_g152734(player, 10_000);
        vm.prank(player);
        coinflip.playCoinflip(0, 10_000);

        (, , uint256 carry1, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carry1, carry0, "no reachable path moved the carry riding the unapplied day");
    }

    /// Applied flip, take-profit bank present: a burn shortfall drains the bank first, then the
    /// carry, and the position stays on auto-rebuy.
    function test_UnfrozenBurnSpendsBankFirstThenCarry() public {
        _enterRebuyWithStake(50_000);
        _resolveDay(3, true); // applied, clock still on day 3: not frozen
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0); // settle
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        uint256 bank = coinflip.previewClaimCoinflips(player);
        assertGt(bank, 0, "precondition: a banked take-profit chunk");
        assertGt(carry, 1_000, "precondition: a carry");

        vm.prank(ContractAddresses.COIN);
        uint256 consumed = coinflip.consumeCoinflipsForBurn(player, bank + 1_000);

        assertEq(consumed, bank + 1_000, "bank plus the shortfall from carry");
        assertEq(coinflip.previewClaimCoinflips(player), 0, "bank drained first");
        (bool enabled, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertTrue(enabled, "still on auto-rebuy");
        assertEq(carryAfter, carry - 1_000, "only the shortfall left the carry");
    }

    /// The burn caps at bank plus carry and never touches more.
    function test_UnfrozenBurnCapsAtBankPlusCarry() public {
        _enterRebuyWithStake(50_000);
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        uint256 bank = coinflip.previewClaimCoinflips(player);

        vm.prank(ContractAddresses.COIN);
        uint256 consumed = coinflip.consumeCoinflipsForBurn(player, type(uint128).max);

        assertEq(consumed, bank + carry);
        (bool enabled, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertTrue(enabled);
        assertEq(carryAfter, 0);
    }

    /// Through FLIP's real gameplay burn: with an empty wallet and bank, the burn reverts while
    /// the carry rides an unapplied day and succeeds from the carry once that day applies; the
    /// remainder keeps compounding.
    function test_GameplayBurnSpendsCarryOnlyOnceTheFlipApplies() public {
        _enterRebuyWithStake(); // 0 take-profit: every win rolls, nothing banks
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0);
        _warpToDay(4); // day 4 requested, unapplied: frozen
        assertEq(coin.balanceOf(player), 0, "precondition: empty wallet");

        vm.prank(GAME);
        vm.expectRevert(FLIP.Insufficient.selector);
        coin.burnCoin_g27673(player, 1_000);

        _resolveDay(4, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        vm.prank(GAME);
        coin.burnCoin_g27673(player, 1_000);
        (bool enabled, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertTrue(enabled);
        assertEq(carryAfter, carry - 1_000, "the burn spent applied carry");

        _resolveDay(5, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0);
        (, , uint256 carryNext, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryNext, _carryAfterRide(carry - 1_000, 5), "the remainder kept rolling");
    }

    /// A resolved loss settles before any spend: the wiped carry cannot fund a burn.
    function test_GameplayBurnSettlesALossBeforeSpending() public {
        _enterRebuyWithStake();
        _resolveDay(3, true); // a winning carry, left unsettled
        _resolveDay(4, false); // then a loss, applied
        vm.prank(GAME);
        vm.expectRevert(FLIP.Insufficient.selector);
        coin.burnCoin_g27673(player, 1);
    }

    /// Transfers and claims stay on the bank: an applied carry is reachable only through a
    /// gameplay burn or claimCoinflipCarry.
    function test_TransfersAndClaimsNeverReachTheCarry() public {
        _enterRebuyWithStake();
        _resolveDay(3, true);
        vm.prank(player);
        coinflip.claimCoinflipCarry(0, 0);
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertGt(carry, 0);

        vm.prank(player);
        vm.expectRevert();
        coin.transfer(operator, 1);
        vm.prank(player);
        assertEq(coinflip.claimCoinflips(0, type(uint256).max), 0);
        vm.prank(ContractAddresses.COIN);
        assertEq(coinflip.claimCoinflipsFromFlip(player, type(uint256).max), 0);

        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(player);
        assertEq(carryAfter, carry);
    }

    /// Protocol IDs (VAULT, sDGNRS, GNRUS) never reach a carry through the gameplay consumer;
    /// GNRUS (ID 3, the boundary) holds one, which only its timed backing route spends.
    function test_ProtocolAccountsGameplayBurnNeverReachesCarry() public {
        vm.prank(GAME);
        coinflip.creditFlip_g317(3, 50_000);
        _resolveDay(3, true);
        vm.prank(ContractAddresses.COIN);
        assertEq(coinflip.consumeCoinflipsForBurn(ContractAddresses.GNRUS, 1_000), 0, "no carry for a protocol ID");
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfoById(3);
        assertGt(carry, 0, "precondition: GNRUS holds an applied carry");
        vm.prank(ContractAddresses.COIN);
        assertEq(coinflip.consumeFlipBacking(ContractAddresses.GNRUS, 1_000), 1_000, "the backing route reaches it");
    }

    function test_RevertsWithoutAutoRebuy() public {
        vm.prank(player);
        vm.expectRevert(CoinflipCore.AutoRebuyNotEnabled.selector);
        coinflip.claimCoinflipCarry(0, 1);
    }
    function testUnlimitedRebuyRetainsBothWordsAcrossWinLossAndStopOne() public {
        _enterRebuyWithStake();
        uint32 id = game.walletIdOf_g3120(player);
        bytes32 base = keccak256(abi.encode(uint256(id), uint256(2)));
        _resolveDay(3, true);
        vm.prank(player); coinflip.playCoinflip(0, 0);
        _resolveDay(4, false);
        vm.prank(player); coinflip.playCoinflip(0, 0);
        (bool enabled, uint256 stop, uint256 carry,) = coinflip.coinflipAutoRebuyInfoById(id);
        assertTrue(enabled); assertEq(stop, 0); assertEq(carry, 0);
        assertGt(uint256(vm.load(address(coinflip), base)), 0);
        assertEq(uint256(vm.load(address(coinflip), bytes32(uint256(base) + 1))), 1);
        vm.prank(player); coinflip.setCoinflipAutoRebuyTakeProfit(0, 1);
        (, stop,,) = coinflip.coinflipAutoRebuyInfoById(id);
        assertEq(stop, 1, "real stop one remains distinct");
        vm.prank(player); coinflip.setCoinflipAutoRebuyTakeProfit(0, type(uint128).max);
        (, stop,,) = coinflip.coinflipAutoRebuyInfoById(id);
        assertEq(stop, type(uint128).max, "full stop range preserved");
    }

}
