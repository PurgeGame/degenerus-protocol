// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CoinflipSeedWindow — the VAULT / sDGNRS deploy seed as a fixed day window
/// @notice The seed is never written to a stake lane: the walks add SEED_FLIP_DAILY to a
///         recipient's stake on each of days 1..20 and on no other day.
///         - REF-02 arithmetic: a vault claim and sDGNRS's settled backing equal the payout sum
///           computed by hand from stake = lane + seed.
///         - VIEW-01/02 coinflipAmount and the preview walk carry the seed for the recipients on
///           window days only; no later day, including past x00 levels, is seeded.
///         - ARM-01 the deploy window covers days 1..20 with no lane written and is announced once.
contract CoinflipSeedWindowTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant COIN = ContractAddresses.COIN;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;

    uint256 internal constant SEED = 200_000;
    uint24 internal constant SEED_DAYS = 20;
    bytes32 internal constant STAKE_SIG = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant ARMED_SIG = keccak256("SeedWindowArmed(uint24,uint24,uint256)");

    address internal stranger;

    function setUp() public {
        _deployProtocol();
        stranger = makeAddr("seed_window_stranger");
    }

    // =====================================================================
    //                              helpers
    // =====================================================================

    function _warpToDay(uint24 d) internal {
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
    }

    function _resolve(uint24 d, bool win) internal {
        uint256 word = uint256(keccak256(abi.encodePacked("seed_window_word", d)));
        word = win ? word | 1 : word & ~uint256(1);
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, d);
    }

    function _creditVault(uint256 amount) internal {
        vm.prank(GAME);
        coinflip.creditFlip(1, amount);
    }

    function _creditSdgnrs(uint256 amount) internal {
        vm.prank(COIN);
        coinflip.creditSdgnrsBacking(amount);
    }

    function _vaultClaim(uint256 amount) internal returns (uint256) {
        vm.prank(VAULT);
        return coinflip.claimCoinflips(0, amount);
    }

    function _rawStake(uint24 day, address p) internal view returns (uint256) {
        return CoinflipStorage.read(address(coinflip), game.walletIdOf(p), day);
    }

    function _stateSlot(address p) internal view returns (bytes32) {
        return keccak256(abi.encode(game.walletIdOf(p), uint256(2)));
    }

    function _slot4() internal view returns (uint256) {
        return uint256(vm.load(address(coinflip), bytes32(uint256(4))));
    }

    /// @dev The vault's raw BAF word for bracket 10 (level 0 records to bracket 10).
    function _bafWord(address p) internal view returns (uint256) {
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(uint256(game.walletIdOf(p)), uint256(0)))) + 1);
        return uint256(vm.load(address(jackpots), slot));
    }

    function _setResult(uint24 day, uint8 b) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day >> 5), uint256(1)));
        uint256 w = uint256(vm.load(address(coinflip), slot));
        uint256 shift = (uint256(day) & 31) * 8;
        vm.store(address(coinflip), slot, bytes32((w & ~(uint256(0xFF) << shift)) | (uint256(b) << shift)));
    }

    function _setFlipsClaimableDay(uint24 day) internal {
        uint256 w = _slot4();
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((w & ~uint256(0xFFFFFF)) | uint256(day)));
    }

    function _payout(uint256 stake, uint24 day) internal view returns (uint256) {
        (uint16 r,) = coinflip.getCoinflipDayResult(day);
        return stake + (stake * uint256(r)) / 100;
    }

    // =====================================================================
    //                    REF-02 — arithmetic reference
    // =====================================================================

    /// @dev Credits land on days 3, 10 (seeded) and 22 (not); every resolved day pays
    ///      stake = lane + seed. The vault walks all 22 days in one claim; sDGNRS settles daily,
    ///      folding wins into claimable through day 20 and rolling its carry from day 21.
    function test_SettlementsEqualTheStoredSeedPayoutSum() public {
        uint256[24] memory lane;
        uint256 vaultExpected;
        uint256 vaultLosses;
        uint256 sdgnrsClaimable;
        uint256 sdgnrsCarry;
        uint256 allowance0 = coin.vaultMintAllowance();
        uint256 wwxrpVault0 = wwxrp.claimable(game.walletIdOf(VAULT));
        for (uint24 d = 1; d <= 22; ++d) {
            _warpToDay(d);
            if (d == 2 || d == 9 || d == 21) {
                _creditVault(12_345);
                _creditSdgnrs(9_876);
                lane[d + 1] = 12_345;
            }
            _resolve(d, d % 3 != 0);
            (, bool win) = coinflip.getCoinflipDayResult(d);

            uint256 stake = lane[d] + (d <= SEED_DAYS ? SEED : 0);
            if (win) vaultExpected += _payout(stake, d);
            else if (stake != 0) ++vaultLosses;

            uint256 sStake = (lane[d] == 0 ? 0 : 9_876) + (d <= SEED_DAYS ? SEED : 0) + sdgnrsCarry;
            if (d <= SEED_DAYS) {
                if (win) sdgnrsClaimable += _payout(sStake, d);
            } else if (win) {
                sdgnrsCarry = _payout(sStake, d);
                sdgnrsCarry += (sdgnrsCarry * 75) / 10_000;
            } else {
                sdgnrsCarry = 0;
            }
        }
        assertGt(vaultExpected, 0, "non-vacuous");
        assertGt(sdgnrsCarry, 0, "non-vacuous: day 22 rolled sDGNRS's credit");

        assertEq(coinflip.previewClaimCoinflips(VAULT), vaultExpected, "preview pays lane + seed per winning day");
        assertEq(_vaultClaim(type(uint256).max), vaultExpected, "claim pays lane + seed per winning day");
        assertEq(coin.vaultMintAllowance() - allowance0, vaultExpected, "minted into the vault allowance");
        assertEq(_bafWord(VAULT) & type(uint168).max, vaultExpected, "every winning payout is BAF credit");
        assertEq(wwxrp.claimable(game.walletIdOf(VAULT)) - wwxrpVault0, vaultLosses * 1, "one loss prize per staked losing day");
        assertEq(_vaultClaim(type(uint256).max), 0, "the cursor consumed each seed once");
        assertEq(_rawStake(3, VAULT) + _rawStake(10, VAULT) + _rawStake(22, VAULT), 3 * 12_345, "retained lanes cannot be claimed twice");

        (bool enabled, uint256 stop, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabled, "sDGNRS auto-rebuy armed at epoch 20");
        assertEq(stop, 0);
        assertEq(carry, sdgnrsCarry, "carry rolls lane + carry from day 21");
        uint256 sdgnrsStored = uint128(uint256(vm.load(address(coinflip), _stateSlot(SDGNRS))));
        assertEq(sdgnrsStored, sdgnrsClaimable, "seed-window wins fold into claimableStored");
    }

    // =====================================================================
    //                    VIEW-01 / VIEW-02 — reads
    // =====================================================================

    function test_CoinflipAmountCarriesTheSeedForRecipientsOnWindowDaysOnly() public {
        address alice = makeAddr("seed_window_alice");
        // Wall day w targets day w + 1: the deploy window is days 1..20.
        for (uint24 w = 1; w <= 21; ++w) {
            _warpToDay(w);
            uint256 expected = w + 1 <= SEED_DAYS ? SEED : 0;
            assertEq(coinflip.coinflipAmount(VAULT), expected, "vault seed on deploy-window days");
            assertEq(coinflip.coinflipAmount(SDGNRS), expected, "sDGNRS seed on deploy-window days");
            assertEq(coinflip.coinflipAmount(alice), 0, "no seed for anyone else");
        }

        _warpToDay(5);
        _creditVault(1_234);
        uint32 aliceId = _giveWalletId(alice);
        vm.prank(GAME);
        coinflip.creditFlip(aliceId, 1_234);
        assertEq(coinflip.coinflipAmount(VAULT), 1_234 + SEED, "seed joins the stored stake");
        assertEq(coinflip.coinflipAmount(alice), 1_234);

        // Nothing seeds again on any later day.
        for (uint24 w = 22; w <= 400; ++w) {
            _warpToDay(w);
            assertEq(coinflip.coinflipAmount(VAULT), 0, "vault carries no seed past the deploy window");
            assertEq(coinflip.coinflipAmount(SDGNRS), 0, "sDGNRS carries no seed past the deploy window");
        }
    }

    /// @dev Results are installed without settling anyone, so the preview walks pending days.
    function test_PreviewWalkCountsTheSeedForRecipientsOnly() public {
        address alice = makeAddr("seed_window_alice");
        uint256 expected;
        for (uint24 d = 1; d <= SEED_DAYS; ++d) {
            bool win = d % 4 != 0;
            _setResult(d, win ? 150 : 1);
            if (win) expected += SEED + (SEED * 150) / 100;
        }
        _setFlipsClaimableDay(SEED_DAYS);
        _warpToDay(SEED_DAYS);

        assertEq(coinflip.previewClaimCoinflips(VAULT), expected, "vault preview includes every seeded win");
        assertEq(coinflip.previewClaimCoinflips(SDGNRS), expected, "sDGNRS preview includes every seeded win");
        assertEq(coinflip.previewFlipBacking(SDGNRS), expected, "salvage backing includes the seed");
        assertEq(coinflip.previewClaimCoinflips(alice), 0, "no seed for anyone else");

        vm.prank(SDGNRS);
        assertEq(coinflip.redeemableFlipBacking(), expected, "settlement equals the preview");
        assertEq(_vaultClaim(type(uint256).max), expected, "claim equals the preview");

        // Days 21..55 all win at 100% and carry no seed.
        _warpToDay(30);
        for (uint24 d = 21; d <= 55; ++d) {
            _setResult(d, 100);
        }
        _setFlipsClaimableDay(55);
        _warpToDay(55);
        assertEq(coinflip.previewClaimCoinflips(VAULT), 0, "no seed after day 20");
        assertEq(coinflip.previewClaimCoinflips(SDGNRS), expected, "sDGNRS adds nothing to its settled backing");
        assertEq(coinflip.previewClaimCoinflips(alice), 0);
        assertEq(_vaultClaim(type(uint256).max), 0);
    }

    // =====================================================================
    //                    ARM-01 — the deploy window
    // =====================================================================

    function test_DeployOpensWindowOneThroughTwentyWithoutLaneWrites() public {
        for (uint24 d; d <= 24; ++d) {
            assertEq(_rawStake(d, VAULT), 0, "no vault lane written at deploy");
            assertEq(_rawStake(d, SDGNRS), 0, "no sDGNRS lane written at deploy");
        }

        vm.recordLogs();
        Coinflip fresh = new Coinflip(new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 armed;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(fresh)) continue;
            assertTrue(logs[i].topics[0] != STAKE_SIG, "deploy emits no stake event");
            if (logs[i].topics[0] == ARMED_SIG) {
                ++armed;
                assertEq(uint256(logs[i].topics[1]), 1, "first day 1");
                (uint24 dayCount, uint256 perDay) = abi.decode(logs[i].data, (uint24, uint256));
                assertEq(dayCount, SEED_DAYS);
                assertEq(perDay, SEED);
            }
        }
        assertEq(armed, 1, "the deploy window is announced once");

        // Day 1 and day 20 pay the seed; day 21 does not.
        uint256 wwxrp0 = wwxrp.claimable(game.walletIdOf(VAULT));
        _warpToDay(1);
        _resolve(1, true);
        assertEq(coinflip.previewClaimCoinflips(VAULT), _payout(SEED, 1), "day 1 is seeded");
        for (uint24 d = 2; d <= 21; ++d) {
            _warpToDay(d);
            _resolve(d, false);
        }
        uint256 before = _vaultClaim(type(uint256).max);
        assertEq(before, _payout(SEED, 1));
        _warpToDay(22);
        _resolve(22, true);
        _resolve(23, true);
        assertEq(coinflip.previewClaimCoinflips(VAULT), 0, "day 21 onward carries no seed");
        assertEq(wwxrp.claimable(game.walletIdOf(VAULT)) - wwxrp0, 19, "days 2..20 lost a seed each; day 21 had no stake");
    }
}
