// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipDeepClaimWorstCaseGas — cold worst case of one full coinflip claim walk
/// @notice Every claim walk is bounded by the one claim window, COIN_CLAIM_DAYS = 90, auto-rebuy
///         included, and always settles through flipsClaimableDay in one call. A walk that could
///         not fit a transaction would brick the account's winnings, so this pins the cold worst
///         case of a full window under 10M and the EIP-7825 per-tx cap (2^24 = 16,777,216):
///         - rebuy off, claimCoinflips;
///         - rebuy on with take-profit, the exit setCoinflipAutoRebuy(false);
///         - a first claim (lastClaim 0), claimCoinflips.
///
/// @dev The worst case is the heaviest per-iteration branch repeated over the whole window:
///      every day RESOLVED (no cheap unresolved skip), every day carrying a stored stake (so
///      every tagged page is read), all wins but one (the win branch runs the take-profit
///      division and the BAF credit accumulation), and a single loss on the last day so the
///      end-of-walk WWXRP loss prize fires beside recordBafFlip and mintForGame. Take-profit 1
///      divides each whole-FLIP payout evenly, so the rolling carry stays 0. The window's first
///      day sits in lane 31 of its result word and lane 6 of its stake word, so the walk crosses
///      the most words a window can: 4 result words and 14 stake words.
///
///      State is installed directly (vm.store) against the authoritative slots
///      (forge inspect storageLayout): coinflipStakeRing slot 0, coinflipDayResultPacked
///      slot 1, playerState slot 2, flipsClaimableDay slot 4 byte-offset 0. The install is
///      read back through the contract's getters and, after the measured call, the exact
///      minted payout proves every day of the window was walked. setUp commits all of it, so
///      each test's first protocol call is the cold measured transaction.
contract CoinflipDeepClaimWorstCaseGas is DeployProtocol {
    // EIP-7825 transaction gas cap (2^24). A claim above this can never be mined.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    // The owner's hard ceiling for an indivisible unit.
    uint256 internal constant GAS_TARGET = 10_000_000;

    uint24 internal constant WINDOW = 90; // COIN_CLAIM_DAYS
    uint256 internal constant STAKE = 1000;
    uint8 internal constant WIN_BYTE = 156; // max win reward%
    uint8 internal constant LOSS_BYTE = 1; // resolved-loss sentinel
    uint128 internal constant TAKE_PROFIT = 1; // divides each payout evenly -> carry stays 0
    // First window day 1343: result lane 31 and stake lane 6 maximize the touched words.
    uint24 internal constant COLD_LATEST = 1432;
    uint24 internal constant FIRST_DAY = COLD_LATEST - WINDOW + 1;
    uint256 internal constant SUPPLIED_GAS = 12_000_000;

    address internal regularPlayer;
    address internal rebuyPlayer;
    address internal firstPlayer;
    bool internal isolated;

    function setUp() public virtual {
        _deployProtocol();
        isolated = vm.envOr("FOUNDRY_ISOLATE", false);
        // The benign purchase window the other coinflip suites use, so the post-walk BAF
        // guard / purchaseInfo_g1027 read behaves as in production.
        _warpToDay(2);
        regularPlayer = makeAddr("regular_claim_player");
        rebuyPlayer = makeAddr("rebuy_claim_player");
        firstPlayer = makeAddr("first_claim_player");
        _installResults(COLD_LATEST, COLD_LATEST);
        _setFlipsClaimableDay(COLD_LATEST);
        _prepare(regularPlayer, COLD_LATEST - WINDOW, false);
        _prepare(rebuyPlayer, COLD_LATEST - WINDOW, true);
        _prepare(firstPlayer, 0, false);
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



    /// @dev A win (WIN_BYTE) on every day in [0, n], then `lossDay` as a resolved loss.
    function _installResults(uint24 n, uint24 lossDay) internal {
        uint256 allWin;
        for (uint256 i = 0; i < 32; ++i) {
            allWin |= uint256(WIN_BYTE) << (i * 8);
        }
        for (uint24 k = 0; k <= (n >> 5); ++k) {
            vm.store(address(coinflip), keccak256(abi.encode(uint256(k), uint256(1))), bytes32(allWin));
        }
        if (lossDay != 0) _setResultDay(lossDay, LOSS_BYTE);
    }

    /// @dev A stake on every day in [0, n] for `p`. Whole-slot writes for speed.
    function _installStakes(address p, uint24 n) internal {
        uint32 id = game.walletIdOf_g3120(p);
        uint24 first = n >= WINDOW ? n - WINDOW + 1 : 0;
        for (uint256 day = first; day <= n; ++day) CoinflipStorage.set(address(coinflip), id, uint24(day), STAKE);
    }

    /// @dev playerState slot 2. word0: claimableStored(0) | lastClaim<<128 |
    ///      autoRebuyStartDay<<152 | autoRebuyEnabled<<176. word1: autoRebuyStop |
    ///      autoRebuyCarry(0)<<128.
    function _installPlayerState(address p, uint24 lastClaim, uint24 startDay, bool rebuyEnabled, uint128 takeProfit)
        internal
    {
        bytes32 base = keccak256(abi.encode(game.walletIdOf_g3120(p), uint256(2)));
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

    function _intrinsic(bytes memory data) internal pure returns (uint256 gas) {
        gas = 21_000;
        for (uint256 i; i < data.length; ++i) gas += data[i] == 0 ? 4 : 16;
    }

    // ----------------------------------------------------------------------
    //                              fixture
    // ----------------------------------------------------------------------

    function _prepare(address target, uint24 lastClaim, bool rebuy) internal {
        _giveWalletId(target);
        _installStakes(target, COLD_LATEST);
        _installPlayerState(target, lastClaim, lastClaim, rebuy, rebuy ? TAKE_PROFIT : 0);

        (uint16 rFirst, bool wFirst) = coinflip.getCoinflipDayResult(FIRST_DAY);
        assertEq(rFirst, WIN_BYTE, "first window day installed as max win");
        assertTrue(wFirst, "first window day is a win");
        (uint16 rLoss, bool wLoss) = coinflip.getCoinflipDayResult(COLD_LATEST);
        assertEq(rLoss, LOSS_BYTE, "last day installed as resolved loss");
        assertFalse(wLoss, "last day is a loss");
        (bool en, uint256 stop, uint256 carry, uint24 sd) = coinflip.coinflipAutoRebuyInfo(target);
        assertEq(en, rebuy, "auto-rebuy mode installed");
        assertEq(stop, rebuy ? TAKE_PROFIT : 0, "take-profit installed");
        assertEq(carry, 0, "carry starts 0");
        assertEq(sd, lastClaim, "rebuy start day installed");
        assertEq(coin.balanceOf(target), 0, "fixture starts without minted winnings");
    }

    function _claimData() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("claimCoinflips(uint32,uint256)", uint32(0), type(uint256).max);
    }

    function _exitData() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("setCoinflipAutoRebuy(uint32,bool,uint256)", uint32(0), false, uint256(0));
    }

    /// @dev One cold call from `p`; returns its execution gas (intrinsic excluded).
    function _call(address p, bytes memory data) internal returns (uint256 exec) {
        vm.prank(p);
        (bool ok,) = address(coinflip).call{gas: SUPPLIED_GAS}(data);
        assertTrue(ok, "measured walk succeeds");
        exec = vm.lastCallGas().gasTotalUsed - (isolated ? _intrinsic(data) : 0);
    }

    /// @dev Every day of the window was walked: 89 win payouts minted, the last day lost, the
    ///      cursor at the frontier, and rebuy off (the exit disables it; the others never had it).
    function _assertWholeWindow(address p) internal view {
        assertEq(
            coin.balanceOf(p),
            uint256(WINDOW - 1) * _winPayout(),
            "settled & minted exactly 89 win payouts (proves all 90 days walked)"
        );
        bytes32 base = keccak256(abi.encode(game.walletIdOf_g3120(p), uint256(2)));
        assertEq(uint24(uint256(vm.load(address(coinflip), base)) >> 128), COLD_LATEST, "cursor at the frontier");
        (bool enAfter,,,) = coinflip.coinflipAutoRebuyInfo(p);
        assertFalse(enAfter, "rebuy off after the walk");
    }

    function _report(string memory label, uint256 exec, bytes memory data) internal {
        uint256 txGas = exec + _intrinsic(data);
        emit log_named_uint(string.concat(label, "_exec_gas"), exec);
        emit log_named_uint(string.concat(label, "_tx_gas_incl_intrinsic"), txGas);
        assertLt(txGas, GAS_TARGET, "a full 90-day walk stays under 10M");
        assertLt(txGas, EIP7825_TX_GAS_CAP, "and under the EIP-7825 per-tx cap");
    }

    // ----------------------------------------------------------------------
    //                               tests
    // ----------------------------------------------------------------------

    function test_Claim90DaysRebuyOffCold() public {
        uint256 exec = _call(regularPlayer, _claimData());
        _assertWholeWindow(regularPlayer);
        _report("claim_90_rebuy_off", exec, _claimData());
    }

    function test_Exit90DaysRebuyOnTakeProfitCold() public {
        uint256 exec = _call(rebuyPlayer, _exitData());
        _assertWholeWindow(rebuyPlayer);
        _report("exit_90_rebuy_on_tp1", exec, _exitData());
    }

    function test_FirstClaim90DaysCold() public {
        uint256 exec = _call(firstPlayer, _claimData());
        _assertWholeWindow(firstPlayer);
        _report("first_claim_90", exec, _claimData());
    }
}
