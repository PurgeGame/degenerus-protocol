// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The stored-seed rule, as a reference: writes the active window's seed into both
///      recipients' stake lanes (stake = lane + SEED_FLIP_DAILY on every window day) and parks the
///      window start where no reachable day falls inside it, so the production walk then reads
///      the seed from the lanes alone. Etched over the protocol's Coinflip for one call.
contract StoredSeedReference is CoinflipStakeSetter {
    function materializeSeedWindow() external {
        uint24 start = seedWindowStart;
        for (uint24 i; i < 20; ++i) {
            uint24 d = start + i;
            _setFlipStake(d, 1, _flipStake(d, 1) + 200_000);
            _setFlipStake(d, 2, _flipStake(d, 2) + 200_000);
        }
        seedWindowStart = type(uint24).max;
    }
}

/// @title CoinflipSeedWindow — the VAULT / sDGNRS seed program as one stored window start
/// @notice The seed is never written to a stake lane: Coinflip keeps the active window's first
///         day and the walks add SEED_FLIP_DAILY to a recipient's stake on each window day.
///         - REF-01 differential: every observable of VAULT and sDGNRS (settled claimable, carry,
///           cursor, auto-rebuy state, minted FLIP, WWXRP loss prizes, the vault's BAF bracket
///           credit, previews, salvage and redemption backing) matches the stored-seed rule, run
///           side by side over wins, losses, credits on seeded days, partial claims, the vault on
///           and off auto-rebuy, two century windows and claim-window expiry.
///         - REF-02 arithmetic: a vault claim and sDGNRS's settled backing equal the payout sum
///           computed by hand from stake = lane + seed.
///         - VIEW-01/02 coinflipAmount and the preview walk carry the seed for the recipients on
///           window days only.
///         - ARM-01/02 arming writes only the window word, keeps the seeds off the BAF draw and
///           the flip record; the deploy window covers days 1..20 with no lane written.
contract CoinflipSeedWindowTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant COIN = ContractAddresses.COIN;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;

    uint256 internal constant SEED = 200_000;
    uint24 internal constant SEED_DAYS = 20;
    uint256 internal constant FIELDS = 19;
    bytes32 internal constant STAKE_SIG = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant ARMED_SIG = keccak256("SeedWindowArmed(uint24,uint24,uint24,uint256)");

    address internal stranger;

    struct Trace {
        uint256[] v;
        uint256 n;
    }

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

    /// @dev Production arm; the reference path then moves the window's seed into the lanes.
    function _arm(uint24 lvl, bool stored) internal {
        vm.prank(GAME);
        coinflip.armCenturySeed(lvl);
        if (stored) _materialize();
    }

    function _materialize() internal {
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(StoredSeedReference).runtimeCode);
        StoredSeedReference(address(coinflip)).materializeSeedWindow();
        vm.etch(address(coinflip), code);
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
        bytes32 inner = keccak256(abi.encode(uint256(day >> 3), uint256(0)));
        uint256 w = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint256(game.walletIdOf(p)), uint256(inner)))));
        return uint256(uint32(w >> ((uint256(day) & 7) * 32)));
    }

    function _stateSlot(address p) internal view returns (bytes32) {
        return keccak256(abi.encode(game.walletIdOf(p), uint256(2)));
    }

    function _slot4() internal view returns (uint256) {
        return uint256(vm.load(address(coinflip), bytes32(uint256(4))));
    }

    function _windowStart() internal view returns (uint24) {
        return uint24(_slot4() >> 200);
    }

    /// @dev The vault's raw BAF word for bracket 10 (level 0 records to bracket 10).
    function _bafWord(address p) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(10), uint256(0)));
        return uint256(vm.load(address(jackpots), keccak256(abi.encode(uint256(game.walletIdOf(p)), uint256(inner)))));
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

    /// @dev Every VAULT / sDGNRS observable the two seed representations must agree on.
    function _observe(Trace memory t) internal view {
        uint256 n = t.n;
        uint256[] memory v = t.v;
        v[n++] = coinflip.coinflipAmount(VAULT);
        v[n++] = coinflip.coinflipAmount(SDGNRS);
        v[n++] = coinflip.previewClaimCoinflips(VAULT);
        v[n++] = coinflip.previewClaimCoinflips(SDGNRS);
        v[n++] = coinflip.previewFlipBacking(VAULT);
        v[n++] = coinflip.previewFlipBacking(SDGNRS);
        v[n++] = uint256(vm.load(address(coinflip), _stateSlot(VAULT)));
        v[n++] = uint256(vm.load(address(coinflip), bytes32(uint256(_stateSlot(VAULT)) + 1)));
        v[n++] = uint256(vm.load(address(coinflip), _stateSlot(SDGNRS)));
        v[n++] = uint256(vm.load(address(coinflip), bytes32(uint256(_stateSlot(SDGNRS)) + 1)));
        v[n++] = coin.vaultMintAllowance();
        v[n++] = coin.totalSupply();
        v[n++] = wwxrp.claimable(game.walletIdOf(VAULT));
        v[n++] = wwxrp.claimable(game.walletIdOf(SDGNRS));
        v[n++] = _bafWord(VAULT);
        v[n++] = (_slot4() >> 24) & 0xFF; // sdgnrsAutoRebuyArmed
        v[n++] = _slot4() & 0xFFFFFF; // flipsClaimableDay
        v[n++] = (_slot4() >> 152) & 0xFFFFFF; // lastSeededCentury
        v[n++] = coin.balanceOf(stranger);
        t.n = n;
    }

    function _newTrace() internal pure returns (Trace memory t) {
        t.v = new uint256[](FIELDS * 400);
    }

    function _assertSameTrace(Trace memory a, Trace memory b) internal pure {
        assertEq(a.n, b.n, "both runs observe the same number of steps");
        for (uint256 i; i < a.n; ++i) {
            if (a.v[i] != b.v[i]) {
                revert(
                    string.concat(
                        "seed representations diverge at step ",
                        vm.toString(i / FIELDS),
                        " field ",
                        vm.toString(i % FIELDS),
                        ": window ",
                        vm.toString(a.v[i]),
                        " stored ",
                        vm.toString(b.v[i])
                    )
                );
            }
        }
    }

    // =====================================================================
    //                    REF-01 — differential reference
    // =====================================================================

    /// @dev Runs `scenario` once on production (the window) and once with the seed stored in the
    ///      lanes, from the same snapshot, and compares every observation.
    function _differential(uint256 bits, uint8 scenario) internal returns (Trace memory window) {
        uint256 snap = vm.snapshotState();
        window = _run(bits, scenario, false);
        vm.revertToState(snap);
        Trace memory stored = _run(bits, scenario, true);
        _assertSameTrace(window, stored);
    }

    function _run(uint256 bits, uint8 scenario, bool stored) internal returns (Trace memory t) {
        t = _newTrace();
        if (stored) _materialize();
        _observe(t);
        if (scenario == 0) _windowsAndRebuy(t, bits, stored);
        else _lateVaultAndExpiry(t, bits, stored);
    }

    /// @dev Deploy window with credits on seeded days and partial vault claims; a century window
    ///      the vault rides on auto-rebuy (carry claims, a take-profit change, the deep exit walk
    ///      inside the window); a second century window on default terms; sDGNRS redemption and
    ///      salvage reads throughout.
    function _windowsAndRebuy(Trace memory t, uint256 bits, bool stored) internal {
        for (uint24 d = 1; d <= 95; ++d) {
            _warpToDay(d);
            uint256 r = uint256(keccak256(abi.encode(bits, d)));
            // Credits stake tomorrow, a seeded day for most of the run.
            if (r & 2 != 0) _creditVault(1_000 + ((r >> 8) % 90_000));
            if (r & 4 != 0) _creditSdgnrs(500 + ((r >> 72) % 40_000));
            _resolve(d, r & 1 != 0);

            if (d % 4 == 0 && d < 40) _vaultClaim((r >> 136) % 400_000);
            if (d == 10 || d == 62 || d == 75) {
                // Anyone may settle the vault; day 62 passes the first century window before
                // the second arms.
                vm.prank(stranger);
                coinflip.depositCoinflip(1, 0);
            }
            if (d == 13 || d == 47 || d == 82) {
                vm.prank(SDGNRS);
                uint256 backing = coinflip.redeemableFlipBacking();
                vm.prank(SDGNRS);
                coinflip.withdrawRedeemedFlip(backing / 4);
            }
            if (d == 17 || d == 52) {
                uint256 salvage = coinflip.previewFlipBacking(VAULT);
                vm.prank(COIN);
                coinflip.consumeFlipBacking(VAULT, salvage / 3);
            }
            if (d == 40) {
                vm.prank(VAULT);
                coinflip.setCoinflipAutoRebuy(0, true, 150_000 + ((r >> 200) % 300_000));
                // The century arm rides the day's transition close; a credit already sits on day 41.
                _arm(100, stored);
            }
            if (d == 44 || d == 49) {
                vm.prank(VAULT);
                coinflip.claimCoinflipCarry(0, (r >> 140) % 250_000);
            }
            if (d == 46) {
                vm.prank(VAULT);
                coinflip.setCoinflipAutoRebuyTakeProfit(0, 0);
            }
            if (d == 56) {
                // Leaves auto-rebuy mid-window: the deep walk crosses window days.
                vm.prank(VAULT);
                coinflip.setCoinflipAutoRebuy(0, false, 0);
            }
            if (d == 70) _arm(200, stored);
            if (d == 93) _vaultClaim(type(uint256).max);
            _observe(t);
        }
    }

    /// @dev The vault's first claim lands after the 180-day first-claim window has expired part
    ///      of the deploy window; sDGNRS settles every resolved day. A century window follows and
    ///      the vault claims it only once it has ended.
    function _lateVaultAndExpiry(Trace memory t, uint256 bits, bool stored) internal {
        for (uint24 d = 1; d <= 5; ++d) {
            _warpToDay(d);
            uint256 r = uint256(keccak256(abi.encode(bits, d)));
            if (r & 2 != 0) _creditVault(2_500);
            _resolve(d, r & 1 != 0);
            _observe(t);
        }
        // Days 6..195 resolve in recovery-sized runs at 100% reward.
        for (uint24 start = 6; start < 196; start += 31) {
            uint24 end = start + 31 > 196 ? 196 : start + 31;
            _warpToDay(end - 1);
            vm.prank(GAME);
            coinflip.processCoinflipGap(uint256(keccak256(abi.encode(bits, "gap", start))), start, end);
            _observe(t);
        }
        _warpToDay(195);
        _vaultClaim(type(uint256).max);
        _observe(t);
        _arm(150, stored);
        _observe(t);
        for (uint24 d = 196; d <= 220; ++d) {
            _warpToDay(d);
            uint256 r = uint256(keccak256(abi.encode(bits, d)));
            if (r & 2 != 0) _creditVault(7_000);
            if (r & 4 != 0) _creditSdgnrs(3_000);
            _resolve(d, r & 1 != 0);
            _observe(t);
        }
        _vaultClaim(type(uint256).max);
        _observe(t);
    }

    /// forge-config: default.fuzz.runs = 24
    function testFuzz_WindowMatchesStoredSeedAcrossWindowsAndRebuy(uint256 bits) public {
        Trace memory t = _differential(bits, 0);
        assertGt(t.n, FIELDS * 90, "non-vacuous: the run observed every day");
        assertGt(coin.vaultMintAllowance(), 0, "non-vacuous: the vault minted surviving seed");
        assertGt(_bafWord(VAULT) & type(uint192).max, 0, "non-vacuous: the vault recorded BAF credit");
    }

    /// forge-config: default.fuzz.runs = 12
    function testFuzz_WindowMatchesStoredSeedThroughExpiry(uint256 bits) public {
        _differential(bits, 1);
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
        assertEq(_bafWord(VAULT) & type(uint192).max, vaultExpected, "every winning payout is BAF credit");
        assertEq(wwxrp.claimable(game.walletIdOf(VAULT)) - wwxrpVault0, vaultLosses * 1, "one loss prize per staked losing day");
        assertEq(_vaultClaim(type(uint256).max), 0, "the cursor consumed each seed once");
        assertEq(_rawStake(3, VAULT) + _rawStake(10, VAULT) + _rawStake(22, VAULT), 0, "stored lanes cleared");

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

        // Century window armed on wall day 60: days 61..80.
        _warpToDay(60);
        vm.prank(GAME);
        coinflip.armCenturySeed(100);
        for (uint24 w = 59; w <= 81; ++w) {
            _warpToDay(w);
            uint256 expected = w + 1 >= 61 && w + 1 <= 80 ? SEED : 0;
            assertEq(coinflip.coinflipAmount(VAULT), expected, "vault seed on century-window days");
            assertEq(coinflip.coinflipAmount(SDGNRS), expected, "sDGNRS seed on century-window days");
            assertEq(coinflip.coinflipAmount(alice), 0);
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

        // Century window 31..50 armed on wall day 30; days 21..55 all win at 100%.
        _warpToDay(30);
        vm.prank(GAME);
        coinflip.armCenturySeed(100);
        for (uint24 d = 21; d <= 55; ++d) {
            _setResult(d, 100);
        }
        _setFlipsClaimableDay(55);
        _warpToDay(55);
        uint256 window = uint256(SEED_DAYS) * 2 * SEED;
        assertEq(coinflip.previewClaimCoinflips(VAULT), window, "only days 31..50 carry the seed");
        assertEq(coinflip.previewClaimCoinflips(SDGNRS), expected + window, "on top of its settled backing");
        assertEq(coinflip.previewClaimCoinflips(alice), 0);
        assertEq(_vaultClaim(type(uint256).max), window);
    }

    // =====================================================================
    //                    ARM-01 / ARM-02 — the window itself
    // =====================================================================

    function test_ArmWritesOnlyTheWindowWord() public {
        _warpToDay(60);
        vm.prank(GAME);
        coinflip.armBafDraw(61);
        uint256 lanesBefore;
        for (uint24 d = 56; d <= 88; ++d) lanesBefore += _rawStake(d, VAULT) + _rawStake(d, SDGNRS);

        vm.recordLogs();
        vm.record();
        vm.prank(GAME);
        coinflip.armCenturySeed(100);
        (, bytes32[] memory writes) = vm.accesses(address(coinflip));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertGt(writes.length, 0, "the arm writes");
        for (uint256 i; i < writes.length; ++i) {
            assertEq(writes[i], bytes32(uint256(4)), "only the packed window word is written");
        }
        uint256 armed;
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != STAKE_SIG, "no per-day stake event");
            if (logs[i].topics[0] == ARMED_SIG) {
                ++armed;
                assertEq(uint256(logs[i].topics[1]), 1, "century 1");
                assertEq(uint256(logs[i].topics[2]), 61, "first day = tomorrow");
                (uint24 dayCount, uint256 perDay) = abi.decode(logs[i].data, (uint24, uint256));
                assertEq(dayCount, SEED_DAYS);
                assertEq(perDay, SEED);
            }
        }
        assertEq(armed, 1, "one SeedWindowArmed");
        assertEq(_windowStart(), 61, "window start stored");
        assertEq((_slot4() >> 152) & 0xFFFFFF, 1, "century counter advanced");

        uint256 lanesAfter;
        for (uint24 d = 56; d <= 88; ++d) lanesAfter += _rawStake(d, VAULT) + _rawStake(d, SDGNRS);
        assertEq(lanesAfter, lanesBefore, "no stake lane moved");
        (uint24 drawDay,, uint32 entries) = coinflip.bafDrawInfo();
        assertEq(drawDay, 61);
        assertEq(entries, 0, "seeds never enter the BAF weighted draw");
        assertEq(coinflip.biggestFlipEver(), 0, "seeds never touch the flip record");

        // A repeat inside the century changes nothing and announces nothing.
        uint256 word = _slot4();
        vm.recordLogs();
        vm.prank(GAME);
        coinflip.armCenturySeed(150);
        assertEq(_slot4(), word, "a repeat arm is a silent no-op");
        assertEq(vm.getRecordedLogs().length, 0, "and emits nothing");
    }

    function test_DeployOpensWindowOneThroughTwentyWithoutLaneWrites() public {
        assertEq(_windowStart(), 1, "the protocol's window starts at day 1");
        for (uint24 d; d <= 24; ++d) {
            assertEq(_rawStake(d, VAULT), 0, "no vault lane written at deploy");
            assertEq(_rawStake(d, SDGNRS), 0, "no sDGNRS lane written at deploy");
        }

        vm.recordLogs();
        Coinflip fresh = new Coinflip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 armed;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(fresh)) continue;
            assertTrue(logs[i].topics[0] != STAKE_SIG, "deploy emits no stake event");
            if (logs[i].topics[0] == ARMED_SIG) {
                ++armed;
                assertEq(uint256(logs[i].topics[1]), 0, "century 0");
                assertEq(uint256(logs[i].topics[2]), 1, "first day 1");
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
