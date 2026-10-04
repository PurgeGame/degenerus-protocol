// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CenturySeedWindow — the x00 re-arm of the deploy seed, driven from the level end.
///
/// @notice `armCenturySeed(lvl)` is GAME-only and rides the advance's transition-close call, the
///         one that reopens the purchase phase. It has no revert paths by design: a revert there
///         would brick the daily crank at a level boundary, so "nothing due" must be a silent
///         no-op. That shapes every test here — the assertions are on state NOT moving rather
///         than on reverts.
///
///         - SEED-01 below the first century it is a no-op, not a revert.
///         - SEED-02 it seeds exactly SEED_FLIP_DAILY on each of the 20 days, to both
///           recipients, starting at the next unresolved day.
///         - SEED-03 one century, one arm: a repeat call at the same level changes nothing.
///         - SEED-04 the seed ADDS to a day's existing stake rather than replacing it: sDGNRS is
///           on perpetual auto-rebuy by level 100, so a stake it already rolled forward onto a
///           window day must survive the arm.
///         - SEED-05 a later century re-opens it at that century's target day.
///         - SEED-06 catch-up: arriving a century late claims the SKIPPED one first.
///         - SEED-07 century arming never mints WWXRP; its owner mint is uncapped.
///         - SEED-08 only GAME may call it.
///         The window is one stored start day (Coinflip slot 4, byte 25) and arming writes no
///         stake lane; the walks add the seed on window days.
contract CenturySeedWindow is DeployProtocol {
    uint256 internal constant SEED_FLIP_DAILY = 200_000 ether;
    uint24 internal constant SEED_FLIP_DAYS = 20;
    bytes32 internal constant ARMED_SIG = keccak256("SeedWindowArmed(uint24,uint24,uint24,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// @dev The arm takes its level from the caller, so driving it is a prank plus the level
    ///      the advance would have passed at that phase end.
    function _arm(uint24 lvl) internal {
        vm.prank(address(game));
        coinflip.armCenturySeed(lvl);
    }

    /// @dev Stake standing for `who` on the day `offset` days after the next unresolved one.
    ///      `coinflipAmount` reads at `_targetFlipDay()`, so walking the wall clock forward is
    ///      how a future day's lane is observed. Uses `vm.getBlockTimestamp()` rather than
    ///      chaining off `block.timestamp`, which via-IR folds to a single value.
    function _stakeAtOffset(address who, uint24 offset) internal returns (uint256 amount) {
        uint256 t0 = vm.getBlockTimestamp();
        vm.warp(t0 + uint256(offset) * 1 days);
        amount = coinflip.coinflipAmount(who);
        vm.warp(t0);
    }

    /// @dev Coinflip slot 4 packs lastSeededCentury at byte 19 and the window start at byte 25.
    function _lastSeededCentury() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(coinflip), bytes32(uint256(4)))) >> 152);
    }

    function _windowStart() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(coinflip), bytes32(uint256(4)))) >> 200);
    }

    /// @dev Moves the wall clock past the deploy window (days 1..20).
    function _leaveDeployWindow() internal {
        vm.warp(vm.getBlockTimestamp() + 40 days);
    }

    // ------------------------------------------------------------------
    // SEED-01 / 03 / 05 / 08 — the gate, all silent
    // ------------------------------------------------------------------

    function testBelowFirstCenturyIsASilentNoOp() public {
        uint256 v = _stakeAtOffset(ContractAddresses.VAULT, 0);
        uint256 w = wwxrp.totalSupply();
        _arm(99);
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), v, "no stake written below level 100");
        assertEq(wwxrp.totalSupply(), w, "no WWXRP paid below level 100");
    }

    function testOneArmPerCentury() public {
        _arm(100);
        uint256 v = _stakeAtOffset(ContractAddresses.VAULT, 0);
        uint256 w = wwxrp.totalSupply();

        // Every later phase-end inside the same century calls this again; all must be no-ops.
        _arm(100);
        _arm(150);
        _arm(199);
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), v, "century 1 armed exactly once");
        assertEq(wwxrp.totalSupply(), w, "century arming never mints WWXRP");
    }

    function testNextCenturyReopens() public {
        _leaveDeployWindow();
        _arm(100);
        uint24 first = _windowStart();
        // Centuries are at least 100 levels, and so at least 100 days, apart.
        vm.warp(vm.getBlockTimestamp() + 150 days);
        _arm(200);
        assertEq(_lastSeededCentury(), 2, "second century armed");
        assertEq(_windowStart(), first + 150, "the window re-opens at the second century's target day");
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), SEED_FLIP_DAILY, "first day seeded");
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, SEED_FLIP_DAYS - 1), SEED_FLIP_DAILY, "last day seeded");
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, SEED_FLIP_DAYS), 0, "the window stops at SEED_FLIP_DAYS");
    }

    function testOnlyGameMayArm() public {
        vm.expectRevert(Coinflip.OnlyDegenerusGame.selector);
        coinflip.armCenturySeed(100);
    }

    // ------------------------------------------------------------------
    // SEED-06 — catch-up across a skipped century
    // ------------------------------------------------------------------

    /// @dev Catch-up arms each missed century once, starting with century one.
    function testLateArmClaimsTheSkippedCenturyFirst() public {
        _leaveDeployWindow();
        uint24[3] memory announced;
        for (uint256 i; i < 3; ++i) {
            vm.recordLogs();
            _arm(250);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics[0] == ARMED_SIG) announced[i] = uint24(uint256(logs[j].topics[1]));
            }
        }
        assertEq(announced[0], 1, "century one first");
        assertEq(announced[1], 2, "then the skipped century two");
        assertEq(announced[2], 0, "level 250 has nothing further due");
        assertEq(_lastSeededCentury(), 2);
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), SEED_FLIP_DAILY, "one window, one seed per day");
    }

    // ------------------------------------------------------------------
    // SEED-02 — the window it writes
    // ------------------------------------------------------------------

    function testSeedsEveryDayForBothRecipients() public {
        _leaveDeployWindow();
        // Snapshot first: the property is "every day grew by exactly one seed".
        uint256[21] memory vaultBefore;
        uint256[21] memory sdgnrsBefore;
        for (uint24 d = 0; d <= SEED_FLIP_DAYS; ++d) {
            vaultBefore[d] = _stakeAtOffset(ContractAddresses.VAULT, d);
            sdgnrsBefore[d] = _stakeAtOffset(ContractAddresses.SDGNRS, d);
        }

        _arm(100);

        for (uint24 d = 0; d < SEED_FLIP_DAYS; ++d) {
            assertEq(
                _stakeAtOffset(ContractAddresses.VAULT, d) - vaultBefore[d],
                SEED_FLIP_DAILY,
                "VAULT seeded on every day of the window"
            );
            assertEq(
                _stakeAtOffset(ContractAddresses.SDGNRS, d) - sdgnrsBefore[d],
                SEED_FLIP_DAILY,
                "sDGNRS seeded on every day of the window"
            );
        }

        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, SEED_FLIP_DAYS),
            vaultBefore[SEED_FLIP_DAYS],
            "the window stops at SEED_FLIP_DAYS"
        );
    }

    // ------------------------------------------------------------------
    // SEED-04 — add, never replace
    // ------------------------------------------------------------------

    function testAddsToAnExistingStakeInsteadOfReplacingIt() public {
        _leaveDeployWindow();
        // Give sDGNRS a standing stake on the window's first day, the way auto-rebuy would.
        vm.prank(address(game));
        coinflip.creditFlip(ContractAddresses.SDGNRS, 12_345 ether);

        uint256 before = _stakeAtOffset(ContractAddresses.SDGNRS, 0);
        assertGt(before, 0, "non-vacuous: sDGNRS holds a stake before arming");

        _arm(100);

        assertEq(
            _stakeAtOffset(ContractAddresses.SDGNRS, 0),
            before + SEED_FLIP_DAILY,
            "the seed adds to the standing stake rather than replacing it"
        );
    }

    // ------------------------------------------------------------------
    // SEED-07 — owner minting replaces automatic WWXRP allocations
    // ------------------------------------------------------------------

    function testCenturiesDoNotMintWwxrp() public {
        uint256 supply = wwxrp.totalSupply();
        uint256 balance = wwxrp.balanceOf(ContractAddresses.VAULT);
        _arm(100);
        _arm(200);
        assertEq(wwxrp.totalSupply(), supply);
        assertEq(wwxrp.balanceOf(ContractAddresses.VAULT), balance);
    }

    // ------------------------------------------------------------------
    // Cost, since it now rides a real transaction
    // ------------------------------------------------------------------

    /// @dev At an x00 level the window sits far past the deploy window. Arming writes the one
    ///      packed word that holds the window start. This is the figure the hosting phase-end tx pays.
    function testArmGasOnVirginDays() public {
        _leaveDeployWindow();
        vm.prank(address(game));
        uint256 g0 = gasleft();
        coinflip.armCenturySeed(100);
        uint256 used = g0 - gasleft();
        emit log_named_uint("armCenturySeed_gas_virgin_days", used);
        assertLt(used, 15_000, "the century arm is one packed-word write");
    }

    // ------------------------------------------------------------------
    // BRICK-SAFETY — the arm rides the daily crank, so it must be TOTAL
    // ------------------------------------------------------------------
    // `armCenturySeed` is called from `mineFlip`'s transition close. A revert anywhere
    // inside it does not fail one feature, it stalls the daily crank at a level boundary —
    // the game cannot leave the jackpot phase. These pin the two arithmetic sites that could
    // ever throw, plus the whole schedule end to end.

    /// @dev Repeated century arming remains bounded and only seeds FLIP.
    function testRepeatedCenturiesNeverRevertOrMintWwxrp() public {
        uint256 supply = wwxrp.totalSupply();
        for (uint24 century = 1; century <= 70; ++century) {
            _arm(century * 100);
            assertEq(_lastSeededCentury(), century);
            assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), SEED_FLIP_DAILY, "one seed per window day");
            assertEq(wwxrp.totalSupply(), supply);
        }
    }

    /// @dev The other arithmetic site. Stakes ADD into a 32-bit whole-FLIP lane that clamps
    ///      instead of reverting. Arming writes no lane at all, so a lane already at its ceiling
    ///      cannot stall the crank; the seed rides on top of the stored lane.
    function testFlipLaneSaturatesRatherThanRevertingTheCrank() public {
        vm.prank(address(game));
        coinflip.creditFlip(ContractAddresses.VAULT, type(uint128).max);
        uint256 cap = uint256(type(uint32).max) * 1 ether;
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), cap + SEED_FLIP_DAILY, "deploy seed on a capped lane");
        for (uint24 century = 1; century <= 90; ++century) {
            _arm(century * 100); // must not revert even with the lane at its ceiling
        }
        assertEq(_lastSeededCentury(), 90, "every arm landed");
        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, 0),
            cap + SEED_FLIP_DAILY,
            "the stored lane stays clamped at its width and the seed adds once"
        );
    }

    /// @dev The century counter itself. `lastSeededCentury + 1` is a checked uint24 add, but
    ///      the level gate bounds it: a century only advances once `lvl >= century * 100`, and
    ///      `lvl` is uint24, so the counter cannot pass 167,772 — far short of uint24 overflow.
    function testCenturyCounterCannotOverflowItsWidth() public {
        uint24 maxLevel = type(uint24).max;
        // The highest century any reachable level can claim.
        uint24 maxCentury = maxLevel / 100;
        assertLt(maxCentury, type(uint24).max, "the counter's ceiling is unreachable by construction");
        // Even the maximum level claims exactly one FLIP window per call.
        _leaveDeployWindow();
        _arm(maxLevel);
        assertEq(_lastSeededCentury(), 1);
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), SEED_FLIP_DAILY);
    }
}
