// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipDeepClaimWorstCaseGas — perma-brick guarantee for the coinflip claim caps
/// @notice The coinflip settle walk is bounded by two caps:
///         COIN_CLAIM_DAYS = 365 (the regular claim window) and
///         AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1460 (the deep walk run when a player
///         turns auto-rebuy OFF and settles every resolved day at once).
///         A claim that cannot fit in a single transaction would perma-brick the
///         player's winnings. This pins the WORST CASE of each cap below the
///         EIP-7825 per-tx gas cap (2^24 = 16,777,216), so neither walk can ever
///         exceed a block.
///
/// @dev The worst case for the deep walk is the heaviest per-iteration branch
///      repeated to the cap: every one of the 1460 days RESOLVED (no cheap
///      unresolved-skip), every day carrying a stored stake (so the lane-clearing
///      SSTORE fires), almost all wins (the win branch runs the take-profit
///      division + the BAF leaderboard accumulation), plus a single loss so the
///      end-of-walk wwxrp loss-prize call also fires alongside recordBafFlip and
///      mintForGame. Take-profit = 1 FLIP divides each whole-FLIP payout
///      evenly, so the rolling carry stays 0 and the compounding payout cannot
///      overflow across 1460 days.
///
///      State is installed directly (vm.store) against the authoritative slots
///      (forge inspect storageLayout): coinflipStakePacked slot 0,
///      coinflipDayResultPacked slot 1, playerState slot 2, flipsClaimableDay slot 4
///      byte-offset 0. The install is
///      proven correct by reading it back through the contract's own getters and,
///      after the measured call, by asserting the exact minted payout — so a future
///      storage-layout drift fails loudly instead of silently mis-measuring.
contract CoinflipDeepClaimWorstCaseGas is DeployProtocol {
    // EIP-7825 transaction gas cap (2^24). A claim above this can never be mined.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    // The advance/afking soft target; a user claim is not in that chain, but the
    // deep walk lands well under it too — reported for visibility.
    uint256 internal constant GAS_TARGET = 10_000_000;

    // Historical WARM regression ceilings, retained unchanged in explicit
    // single-transaction benchmarks. The old seed/proof/claim test body did not
    // reset transaction state; it was not a cold user transaction. Measured 2026-06-13:
    // deep 1460-day = 3,719,531 ; regular 365-day = 944,567.
    uint256 internal constant DEEP_CLAIM_GAS_CEIL = 4_500_000;
    uint256 internal constant REGULAR_CLAIM_GAS_CEIL = 1_200_000;

    uint24 internal constant DEEP_CAP = 1460; // AUTO_REBUY_OFF_CLAIM_DAYS_MAX
    uint24 internal constant WINDOW = 365; // COIN_CLAIM_DAYS
    uint256 internal constant STAKE = 1000 ether;
    uint8 internal constant WIN_BYTE = 156; // max win reward%
    uint8 internal constant LOSS_BYTE = 1; // resolved-loss sentinel
    uint128 internal constant TAKE_PROFIT = 1 ether; // divides each payout evenly -> carry stays 0

    address internal player;
    address internal regularPlayer;
    // 1472 puts the regular 365-day window across 13 packed result words;
    // the deep exit still clamps to days 1..1460 (46 result words, 731 stake words).
    uint24 internal constant COLD_LATEST = 1472;
    uint256 internal constant DEEP_INTRINSIC = 21_448;
    uint256 internal constant REGULAR_INTRINSIC = 21_704;
    uint256 internal constant REVIEW_GAS_CAP = 11_500_000;

    function setUp() public {
        _deployProtocol();
        player = makeAddr("deep_claim_player");
        // Land in the same benign purchase-window the other coinflip suites use,
        // so the post-walk BAF guard / purchaseInfo read behaves as in production.
        _warpToDay(2);
        regularPlayer = makeAddr("regular_claim_player");
        // Seed AND validate in setUp's prior transaction. Each cold test's first
        // production call is the claim, with original SSTORE values already committed.
        _prepareDeep(player, COLD_LATEST);
        _prepareRegular(regularPlayer, COLD_LATEST, DEEP_CAP);
    }

    /// @dev Wall clock just inside GameTimeLib day `d` (mirror of the coinflip suites).
    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    // ----------------------------------------------------------------------
    //                      storage-slot writers (authoritative)
    // ----------------------------------------------------------------------

    /// @dev coinflipDayResultPacked slot 1: 32 days/slot, 8-bit lanes.
    function _setResultDay(uint24 day, uint8 b) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day >> 5), uint256(1)));
        uint256 w = uint256(vm.load(address(coinflip), slot));
        uint256 shift = (uint256(day) & 31) * 8;
        w = (w & ~(uint256(0xFF) << shift)) | (uint256(b) << shift);
        vm.store(address(coinflip), slot, bytes32(w));
    }

    /// @dev coinflipStakePacked slot 0: 2 days/slot, 128-bit lanes, keyed by day>>1 then player.
    function _stakeSlotByKey(uint24 key, address p) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(key), uint256(0)));
        return keccak256(abi.encode(p, uint256(inner)));
    }

    /// @dev Install a win (WIN_BYTE) for every day in [0, n] with a stake on each day,
    ///      then overwrite `lossDay` as a resolved loss. Whole-slot writes for speed.
    function _installResolvedWinsWithStake(address p, uint24 n, uint24 lossDay) internal {
        uint256 allWin;
        for (uint256 i = 0; i < 32; ++i) {
            allWin |= uint256(WIN_BYTE) << (i * 8);
        }
        for (uint24 k = 0; k <= (n >> 5); ++k) {
            vm.store(address(coinflip), keccak256(abi.encode(uint256(k), uint256(1))), bytes32(allWin));
        }
        uint256 stakeWord = STAKE | (STAKE << 128);
        for (uint24 k = 0; k <= (n >> 1); ++k) {
            vm.store(address(coinflip), _stakeSlotByKey(k, p), bytes32(stakeWord));
        }
        if (lossDay != 0) _setResultDay(lossDay, LOSS_BYTE);
    }

    /// @dev playerState slot 2. word0: claimableStored(0) | lastClaim<<128 |
    ///      autoRebuyStartDay<<152 | autoRebuyEnabled<<176. word1: autoRebuyStop |
    ///      autoRebuyCarry(0)<<128.
    function _installPlayerState(address p, uint24 lastClaim, uint24 startDay, bool rebuyEnabled, uint128 takeProfit)
        internal
    {
        bytes32 base = keccak256(abi.encode(p, uint256(2)));
        uint256 w0 = (uint256(lastClaim) << 128) | (uint256(startDay) << 152);
        if (rebuyEnabled) w0 |= uint256(1) << 176;
        vm.store(address(coinflip), base, bytes32(w0));
        vm.store(address(coinflip), bytes32(uint256(base) + 1), bytes32(uint256(takeProfit)));
    }

    /// @dev flipsClaimableDay slot 4, byte-offset 0 (shares the slot with sdgnrsAutoRebuyArmed).
    function _setFlipsClaimableDay(uint24 day) internal {
        bytes32 slot = bytes32(uint256(4));
        uint256 w = uint256(vm.load(address(coinflip), slot));
        w = (w & ~uint256(0xFFFFFF)) | uint256(day);
        vm.store(address(coinflip), slot, bytes32(w));
    }

    function _winPayout() internal pure returns (uint256) {
        return STAKE + (STAKE * uint256(WIN_BYTE)) / 100;
    }

    // ----------------------------------------------------------------------
    //          1. DEEP WALK — auto-rebuy-off settle of the 1460-day cap
    // ----------------------------------------------------------------------

    function _prepareDeep(address target, uint24 latest) private {
        uint24 lossDay = DEEP_CAP; // day 1460 is the single loss

        _installResolvedWinsWithStake(target, DEEP_CAP, lossDay);
        _installPlayerState(target, 0, 0, true, TAKE_PROFIT);
        _setFlipsClaimableDay(latest);

        // Read-back proof the worst-case state is installed where the contract reads it.
        (uint16 r1, bool w1) = coinflip.getCoinflipDayResult(1);
        assertEq(r1, WIN_BYTE, "day 1 installed as max win");
        assertTrue(w1, "day 1 is a win");
        (uint16 rMid,) = coinflip.getCoinflipDayResult(730);
        assertEq(rMid, WIN_BYTE, "mid-range day installed as win");
        (uint16 rLoss, bool wLoss) = coinflip.getCoinflipDayResult(lossDay);
        assertEq(rLoss, LOSS_BYTE, "loss day installed as resolved loss");
        assertFalse(wLoss, "loss day is a loss");
        (bool en, uint256 stop, uint256 carry, uint24 sd) = coinflip.coinflipAutoRebuyInfo(target);
        assertTrue(en, "auto-rebuy armed");
        assertEq(stop, TAKE_PROFIT, "take-profit installed");
        assertEq(carry, 0, "carry starts 0");
        assertEq(sd, 0, "rebuy start day 0");

        assertEq(coin.balanceOf(target), 0, "fixture starts without minted winnings");
    }

    function test_DeepClaim1460DaysFitsUnderTxGasCap() public {
        uint256 used = _measureDeep(player);
        // A packed stake word adds at most 2k cold-read + 2.8k fresh-vs-dirty
        // rewrite gas; reserve 5k. Result words add a cold read. 100k covers
        // fixed player/credit state and cold accounts outside the bounded walk.
        uint256 coldAllowance = (DEEP_CAP / 2 + 1) * 5000 + (DEEP_CAP / 32 + 1) * 2100 + 100_000;
        assertLt(used, DEEP_CLAIM_GAS_CEIL + coldAllowance, "cold deep walk exceeds warm budget plus state allowance");
    }

    function test_DeepClaimWarmSingleTransactionRegression() public {
        assertLt(this.measureWarmDeep(), DEEP_CLAIM_GAS_CEIL, "warm deep walk regressed");
    }

    function measureWarmDeep() external returns (uint256) {
        require(msg.sender == address(this), "test self-call only");
        address target = makeAddr("warm_deep_claim_player");
        // All seed/proof/claim calls are nested under one outer transaction,
        // reproducing the historical benchmark even when --isolate is enabled.
        _prepareDeep(target, DEEP_CAP + 1);
        return _measureDeep(target);
    }

    function _measureDeep(address target) private returns (uint256 gasUsed) {
        // Disabling auto-rebuy runs the deep settle of every resolved day at once.
        vm.prank(target);
        uint256 g0 = gasleft();
        coinflip.setCoinflipAutoRebuy{gas: REVIEW_GAS_CAP - DEEP_INTRINSIC}(address(0), false, 0);
        gasUsed = g0 - gasleft();

        // Correctness anchor: exactly 1459 wins were settled and minted (day 1460 lost).
        uint256 expectedMint = uint256(DEEP_CAP - 1) * _winPayout();
        assertEq(
            coin.balanceOf(target),
            expectedMint,
            "deep walk settled & minted exactly 1459 win payouts (proves all 1460 days processed)"
        );
        (bool enAfter,,,) = coinflip.coinflipAutoRebuyInfo(target);
        assertFalse(enAfter, "auto-rebuy turned off by the exit");

        emit log_named_uint("deep_claim_1460_gas_used", gasUsed);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);
        emit log_named_uint("headroom_to_16p7M_gas", EIP7825_TX_GAS_CAP - gasUsed);

        assertLt(
            gasUsed,
            EIP7825_TX_GAS_CAP,
            "deep 1460-day coinflip settle must fit under the EIP-7825 per-tx gas cap (no perma-brick)"
        );
        assertLt(gasUsed + DEEP_INTRINSIC, REVIEW_GAS_CAP, "deep claim transaction exceeds 11.5M");
    }

    // ----------------------------------------------------------------------
    //          2. REGULAR WINDOW — 365-day claimCoinflips cap
    // ----------------------------------------------------------------------

    function _prepareRegular(address target, uint24 latest, uint24 lossDay) private {
        uint24 lastClaim = latest - WINDOW; // exactly WINDOW resolved days

        _installResolvedWinsWithStake(target, latest, lossDay);
        _installPlayerState(target, lastClaim, 0, false, 0);
        _setFlipsClaimableDay(latest);

        (uint16 rFirst, bool wFirst) = coinflip.getCoinflipDayResult(lastClaim + 1);
        assertEq(rFirst, WIN_BYTE, "first windowed day installed as win");
        assertTrue(wFirst, "first windowed day is a win");
        (uint16 rLoss,) = coinflip.getCoinflipDayResult(lossDay);
        assertEq(rLoss, LOSS_BYTE, "loss day installed");

        assertEq(coin.balanceOf(target), 0, "fixture starts without minted winnings");
    }

    function test_RegularClaim365DayWindowFitsUnderTxGasCap() public {
        uint256 used = _measureRegular(regularPlayer);
        uint256 coldAllowance = (WINDOW / 2 + 1) * 5000 + (WINDOW / 32 + 2) * 2100 + 100_000;
        assertLt(
            used, REGULAR_CLAIM_GAS_CEIL + coldAllowance, "cold regular walk exceeds warm budget plus state allowance"
        );
    }

    function test_RegularClaimWarmSingleTransactionRegression() public {
        assertLt(this.measureWarmRegular(), REGULAR_CLAIM_GAS_CEIL, "warm regular walk regressed");
    }

    function measureWarmRegular() external returns (uint256) {
        require(msg.sender == address(this), "test self-call only");
        address target = makeAddr("warm_regular_claim_player");
        _prepareRegular(target, 1000, 1000);
        return _measureRegular(target);
    }

    function _measureRegular(address target) private returns (uint256 gasUsed) {
        vm.prank(target);
        uint256 g0 = gasleft();
        coinflip.claimCoinflips{gas: REVIEW_GAS_CAP - REGULAR_INTRINSIC}(address(0), type(uint256).max);
        gasUsed = g0 - gasleft();

        // The complete 365-day window contains one loss and exactly 364 wins.
        uint256 expectedMint = uint256(WINDOW - 1) * _winPayout();
        assertEq(
            coin.balanceOf(target),
            expectedMint,
            "regular window settled & minted exactly 364 win payouts (proves the 365-day window walked)"
        );

        emit log_named_uint("regular_claim_365_gas_used", gasUsed);
        emit log_named_uint("headroom_to_16p7M_gas", EIP7825_TX_GAS_CAP - gasUsed);

        assertLt(
            gasUsed, EIP7825_TX_GAS_CAP, "regular 365-day coinflip claim must fit under the EIP-7825 per-tx gas cap"
        );
        assertLt(gasUsed + REGULAR_INTRINSIC, REVIEW_GAS_CAP, "regular claim transaction exceeds 11.5M");
    }
}
