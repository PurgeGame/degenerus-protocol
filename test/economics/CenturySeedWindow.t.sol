// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CenturySeedWindow — the deploy seed is the only seed; x00 levels add none.
///
/// @notice VAULT and sDGNRS each hold SEED_FLIP_DAILY of unstored seed stake on rounds 2..21 and
///         on no other round. Nothing at a century level (100, 200, ...) opens another window.
///
///         - SEED-01 the deploy window seeds exactly SEED_FLIP_DAILY on each of its 20 rounds, to
///           both recipients, and stops after round 21.
///         - SEED-02 no round after the window, at any later century, carries a seed.
///         - SEED-03 the seed ADDS to a day's existing stake rather than replacing it.
///         - SEED-04 the seed never mints WWXRP.
///         - SEED-05 a stake lane at its ceiling clamps; the seed rides on top of the stored lane.
///         - SEED-06 the Coinflip has no GAME-callable seed entry point left.
contract CenturySeedWindow is DeployProtocol {
    uint256 internal constant SEED_FLIP_DAILY = 200_000;
    uint24 internal constant SEED_FLIP_DAYS = 20;
    bytes32 internal constant ARMED_SIG = keccak256("SeedWindowArmed(uint24,uint24,uint256)");

    /// @dev A day-one deployment: Coinflip's logical-day mirror starts at round 1, so every round
    ///      of the window is reachable.
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function setUp() public {
        _deployProtocol();
    }

    /// @dev What each fresh daily request does: the Game moves Coinflip's mirror of the requested
    ///      logical day forward one day at a time, so new stakes target round `day + 1`.
    function _requestDay(uint24 day) internal {
        uint24 requested = coinflip.requestedDailyIdx();
        while (requested < day) {
            ++requested;
            vm.prank(address(game));
            coinflip.onDailyRequest(requested);
        }
        assertEq(coinflip.requestedDailyIdx(), day, "mirror at the requested day");
    }

    /// @dev Standing stake of `who` on flip round `round`, read once the round before it was requested.
    function _stakeOnDay(address who, uint24 round) internal returns (uint256) {
        _requestDay(round - 1);
        return coinflip.coinflipAmount(who);
    }

    // ------------------------------------------------------------------
    // SEED-01 — the deploy window
    // ------------------------------------------------------------------

    function testDeployWindowSeedsEveryDayForBothRecipients() public {
        // The mirror starts at round 1, so the first reachable target is round 2.
        assertEq(coinflip.requestedDailyIdx(), 1, "fixture: a day-one deployment");
        for (uint24 d = 2; d <= SEED_FLIP_DAYS + 1; ++d) {
            assertEq(_stakeOnDay(ContractAddresses.VAULT, d), SEED_FLIP_DAILY, "VAULT seeded on every window day");
            assertEq(_stakeOnDay(ContractAddresses.SDGNRS, d), SEED_FLIP_DAILY, "sDGNRS seeded on every window day");
        }
        assertEq(_stakeOnDay(ContractAddresses.VAULT, SEED_FLIP_DAYS + 2), 0, "the window stops after round 21");
        assertEq(_stakeOnDay(ContractAddresses.SDGNRS, SEED_FLIP_DAYS + 2), 0, "the window stops after round 21");
    }

    function testDeployAnnouncesTheWindowOnce() public {
        vm.recordLogs();
        Coinflip fresh = Coinflip(payable(deployCode("Coinflip.sol:Coinflip", abi.encode(new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0)))));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 armed;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(fresh) || logs[i].topics.length == 0 || logs[i].topics[0] != ARMED_SIG) continue;
            ++armed;
            assertEq(uint256(logs[i].topics[1]), 2, "first round 2");
            (uint24 dayCount, uint256 perDay) = abi.decode(logs[i].data, (uint24, uint256));
            assertEq(dayCount, SEED_FLIP_DAYS);
            assertEq(perDay, SEED_FLIP_DAILY);
        }
        assertEq(armed, 1, "one SeedWindowArmed");
    }

    // ------------------------------------------------------------------
    // SEED-02 — no century seed
    // ------------------------------------------------------------------

    /// @dev Samples the days around the first levels' worth of x00 spacing: a century is at least
    ///      100 levels and so at least 100 days after the window, and none of them is seeded.
    function testNoSeedAfterTheDeployWindow() public {
        uint24[8] memory days_ = [uint24(22), 23, 60, 101, 150, 301, 730, 2_000];
        for (uint256 i; i < days_.length; ++i) {
            assertEq(_stakeOnDay(ContractAddresses.VAULT, days_[i]), 0, "VAULT unseeded after the window");
            assertEq(_stakeOnDay(ContractAddresses.SDGNRS, days_[i]), 0, "sDGNRS unseeded after the window");
        }
    }

    /// @dev A stake credited after the window reads back as exactly that stake.
    function testCreditAfterTheWindowCarriesNoSeed() public {
        _requestDay(299);
        vm.prank(address(game));
        coinflip.creditFlip_g317(1, 12_345);
        vm.prank(address(game));
        coinflip.creditFlip_g317(2, 6_789);
        assertEq(coinflip.coinflipAmount(ContractAddresses.VAULT), 12_345, "vault stake without a seed");
        assertEq(coinflip.coinflipAmount(ContractAddresses.SDGNRS), 6_789, "sDGNRS stake without a seed");
    }

    // ------------------------------------------------------------------
    // SEED-03 — add, never replace
    // ------------------------------------------------------------------

    function testAddsToAnExistingStakeInsteadOfReplacingIt() public {
        // Give sDGNRS a standing stake on a window day, the way auto-rebuy would.
        _requestDay(3);
        vm.prank(address(game));
        coinflip.creditFlip_g317(2, 12_345);
        assertEq(
            coinflip.coinflipAmount(ContractAddresses.SDGNRS),
            12_345 + SEED_FLIP_DAILY,
            "the seed adds to the standing stake rather than replacing it"
        );
    }

    // ------------------------------------------------------------------
    // SEED-04 — owner minting replaces automatic WWXRP allocations
    // ------------------------------------------------------------------

    function testSeedWindowDoesNotMintWwxrp() public {
        uint256 supply = wwxrp.totalSupply();
        uint256 balance = wwxrp.balanceOf(ContractAddresses.VAULT);
        for (uint24 d = 1; d <= SEED_FLIP_DAYS + 5; ++d) {
            _requestDay(d);
            coinflip.coinflipAmount(ContractAddresses.VAULT);
        }
        assertEq(wwxrp.totalSupply(), supply);
        assertEq(wwxrp.balanceOf(ContractAddresses.VAULT), balance);
    }

    // ------------------------------------------------------------------
    // SEED-05 — a capped lane
    // ------------------------------------------------------------------

    /// @dev Stakes ADD into a 32-bit whole-FLIP lane that clamps instead of reverting; the seed
    ///      rides on top of the stored lane on window days only.
    function testFlipLaneSaturatesRatherThanReverting() public {
        _requestDay(1);
        vm.prank(address(game));
        coinflip.creditFlip_g317(1, type(uint128).max);
        uint256 cap = uint256(type(uint32).max);
        assertEq(coinflip.coinflipAmount(ContractAddresses.VAULT), cap + SEED_FLIP_DAILY, "deploy seed on a capped lane");

        vm.prank(address(game));
        coinflip.creditFlip_g317(1, type(uint128).max);
        assertEq(coinflip.coinflipAmount(ContractAddresses.VAULT), cap + SEED_FLIP_DAILY, "the lane stays clamped");
    }

    // ------------------------------------------------------------------
    // SEED-06 — no arm entry point
    // ------------------------------------------------------------------

    function testCoinflipExposesNoSeedArm() public {
        (bool ok,) = address(coinflip).call(abi.encodeWithSignature("armCenturySeed(uint24)", uint24(100)));
        assertFalse(ok, "armCenturySeed is gone");
        vm.prank(address(game));
        (ok,) = address(coinflip).call(abi.encodeWithSignature("armCenturySeed(uint24)", uint24(100)));
        assertFalse(ok, "armCenturySeed is gone for GAME too");
    }
}
