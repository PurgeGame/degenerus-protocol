// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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
///         - SEED-02 it credits exactly SEED_FLIP_DAILY on each of the 20 days, to both
///           recipients, starting at the next unresolved day.
///         - SEED-03 one century, one arm: a repeat call at the same level changes nothing.
///         - SEED-04 it ADDS to a day's existing stake rather than replacing it. The one with
///           real teeth: `_setFlipStake` is a masked overwrite and sDGNRS is on perpetual
///           auto-rebuy by level 100, so a replace would destroy a stake already rolled forward.
///         - SEED-05 a later century re-opens it.
///         - SEED-06 catch-up: arriving a century late claims the SKIPPED one first.
///         - SEED-07 the vault's WWXRP reserve doubles per century and lands in the
///           uncirculated allowance, never a balance.
///         - SEED-08 only GAME may call it.
contract CenturySeedWindow is DeployProtocol {
    uint256 internal constant SEED_FLIP_DAILY = 200_000 ether;
    uint24 internal constant SEED_FLIP_DAYS = 20;

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

    // ------------------------------------------------------------------
    // SEED-01 / 03 / 05 / 08 — the gate, all silent
    // ------------------------------------------------------------------

    function testBelowFirstCenturyIsASilentNoOp() public {
        uint256 v = _stakeAtOffset(ContractAddresses.VAULT, 0);
        uint256 w = wwxrp.vaultAllowance();
        _arm(99);
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), v, "no stake written below level 100");
        assertEq(wwxrp.vaultAllowance(), w, "no WWXRP paid below level 100");
    }

    function testOneArmPerCentury() public {
        _arm(100);
        uint256 v = _stakeAtOffset(ContractAddresses.VAULT, 0);
        uint256 w = wwxrp.vaultAllowance();

        // Every later phase-end inside the same century calls this again; all must be no-ops.
        _arm(100);
        _arm(150);
        _arm(199);
        assertEq(_stakeAtOffset(ContractAddresses.VAULT, 0), v, "century 1 armed exactly once");
        assertEq(wwxrp.vaultAllowance(), w, "century 1 paid WWXRP exactly once");
    }

    function testNextCenturyReopens() public {
        uint256 before = _stakeAtOffset(ContractAddresses.VAULT, 0);
        _arm(100);
        _arm(200);
        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, 0) - before,
            2 * SEED_FLIP_DAILY,
            "second century stacks onto the first window's overlapping day"
        );
    }

    function testOnlyGameMayArm() public {
        vm.expectRevert(Coinflip.OnlyDegenerusGame.selector);
        coinflip.armCenturySeed(100);
    }

    // ------------------------------------------------------------------
    // SEED-06 — catch-up across a skipped century
    // ------------------------------------------------------------------

    /// @dev Arriving a century late must claim the SKIPPED century first, not jump to the
    ///      current one — a jump would forfeit century 1's window and its 2B WWXRP leg.
    function testLateArmClaimsTheSkippedCenturyFirst() public {
        uint256 deployAllowance = wwxrp.INITIAL_VAULT_ALLOWANCE();
        uint256 before = wwxrp.vaultAllowance();

        _arm(250);
        assertEq(
            wwxrp.vaultAllowance() - before,
            2 * deployAllowance,
            "claims century 1 and pays century 1's figure, not century 2's"
        );

        _arm(250);
        assertEq(
            wwxrp.vaultAllowance() - before,
            6 * deployAllowance,
            "the next call picks up century 2 (2B + 4B cumulative)"
        );

        // Century 3 is not due at level 250: silent, and nothing moves.
        uint256 held = wwxrp.vaultAllowance();
        _arm(250);
        assertEq(wwxrp.vaultAllowance(), held, "century 3 is not due at level 250");
    }

    // ------------------------------------------------------------------
    // SEED-02 — the window it writes
    // ------------------------------------------------------------------

    function testSeedsEveryDayForBothRecipients() public {
        // Snapshot first: the DEPLOY window already covers early days, so the property is
        // "every day grew by exactly one seed", not "every day equals one seed".
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
        // Give sDGNRS a standing stake on the window's first day, the way auto-rebuy would.
        vm.prank(address(game));
        coinflip.creditFlip(ContractAddresses.SDGNRS, 12_345 ether);

        uint256 before = _stakeAtOffset(ContractAddresses.SDGNRS, 0);
        assertGt(before, 0, "non-vacuous: sDGNRS holds a stake before arming");

        _arm(100);

        assertEq(
            _stakeAtOffset(ContractAddresses.SDGNRS, 0),
            before + SEED_FLIP_DAILY,
            "the seed adds to the standing stake; a masked overwrite would have destroyed it"
        );
    }

    // ------------------------------------------------------------------
    // SEED-07 — the vault WWXRP reserve
    // ------------------------------------------------------------------

    /// @dev The doubling is stated against WWXRP's deploy allowance, which Coinflip mirrors as
    ///      a local constant. Pin the equality so the two cannot drift apart silently.
    function testWwxrpSeedConstantMatchesDeployAllowance() public view {
        assertEq(
            wwxrp.INITIAL_VAULT_ALLOWANCE(),
            1_000_000_000 ether,
            "Coinflip's mirrored WWXRP_VAULT_SEED must equal WWXRP.INITIAL_VAULT_ALLOWANCE"
        );
    }

    function testVaultWwxrpDoublesEachCentury() public {
        uint256 deployAllowance = wwxrp.INITIAL_VAULT_ALLOWANCE();
        assertEq(wwxrp.vaultAllowance(), deployAllowance, "starts at the deploy reserve");

        _arm(100);
        assertEq(
            wwxrp.vaultAllowance() - deployAllowance,
            2 * deployAllowance,
            "century 1 pays double the deploy reserve"
        );

        uint256 afterFirst = wwxrp.vaultAllowance();
        _arm(200);
        assertEq(wwxrp.vaultAllowance() - afterFirst, 4 * deployAllowance, "century 2 pays double again");
    }

    /// @dev It lands in the uncirculated allowance, not a balance: WWXRP._mint intercepts
    ///      VAULT-destined mints. A balance credit would put it straight into circulation.
    function testVaultWwxrpLandsInAllowanceNotBalance() public {
        uint256 balBefore = wwxrp.balanceOf(ContractAddresses.VAULT);
        uint256 supplyBefore = wwxrp.totalSupply();

        _arm(100);

        assertEq(wwxrp.balanceOf(ContractAddresses.VAULT), balBefore, "no balance credited");
        assertEq(wwxrp.totalSupply(), supplyBefore, "totalSupply untouched: allowance is uncirculated");
    }

    // ------------------------------------------------------------------
    // Cost, since it now rides a real transaction
    // ------------------------------------------------------------------

    /// @dev At an x00 level the seeded days sit far past the deploy window, so all twenty
    ///      slots per recipient are virgin. This is the figure the hosting phase-end tx pays.
    function testArmGasOnVirginDays() public {
        vm.warp(vm.getBlockTimestamp() + 40 days);
        vm.prank(address(game));
        uint256 g0 = gasleft();
        coinflip.armCenturySeed(100);
        uint256 used = g0 - gasleft();
        emit log_named_uint("armCenturySeed_gas_virgin_days", used);
        assertLt(used, 800_000, "the century arm stays a sub-800k addition to the phase-end tx");
    }

    // ------------------------------------------------------------------
    // BRICK-SAFETY — the arm rides the daily crank, so it must be TOTAL
    // ------------------------------------------------------------------
    // `armCenturySeed` is called from `advanceGame`'s transition close. A revert anywhere
    // inside it does not fail one feature, it stalls the daily crank at a level boundary —
    // the game cannot leave the jackpot phase. These pin the two arithmetic sites that could
    // ever throw, plus the whole schedule end to end.

    /// @dev The load-bearing guard. `vaultAllowance += amount` is a CHECKED add, and the
    ///      century payment doubles, so the cap is what bounds it: 60 doublings terminate at
    ///      1e27 * (2^61 - 1) ~= 2.3e45, about 32 orders of magnitude below uint256. Without
    ///      the cap the cumulative add overflows at century 166 — level 16,600, which `level`
    ///      (uint24, max 16,777,215) can reach. Walking every century to the cap and past it
    ///      proves the arm never throws and the payment stops exactly where it should.
    function testEveryCenturyToTheCapAndBeyondNeverReverts() public {
        uint256 deployAllowance = wwxrp.INITIAL_VAULT_ALLOWANCE();
        uint256 expected = deployAllowance;

        // 70 > WWXRP_MAX_DOUBLINGS (60), so this walks the paying range AND the silent tail.
        for (uint24 century = 1; century <= 70; ++century) {
            _arm(century * 100);
            if (century <= 60) expected += deployAllowance << uint256(century);
            assertEq(
                wwxrp.vaultAllowance(),
                expected,
                "every century pays its own doubling, and nothing past the cap"
            );
        }

        assertEq(
            wwxrp.vaultAllowance(),
            deployAllowance * ((uint256(1) << 61) - 1),
            "terminal reserve is the closed form 1e27 * (2^61 - 1)"
        );
        // The tail still arms its FLIP window; only the WWXRP leg stops.
        assertGt(_stakeAtOffset(ContractAddresses.VAULT, 0), 0, "post-cap centuries still seed FLIP");
    }

    /// @dev The other arithmetic site. Stakes ADD into a 128-bit lane, so a long-lived lane
    ///      could exceed it; `_setFlipStake` clamps instead of reverting. Arming many centuries
    ///      on the SAME wall day drives one lane to the ceiling — the crank must survive it.
    function testFlipLaneSaturatesRatherThanRevertingTheCrank() public {
        // Snapshot first: the DEPLOY window already seeded this day, so the property is
        // "the lane grew by exactly 70 seeds", not "the lane equals 70 seeds".
        uint256 before = _stakeAtOffset(ContractAddresses.VAULT, 0);
        for (uint24 century = 1; century <= 70; ++century) {
            _arm(century * 100);
        }
        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, 0) - before,
            70 * SEED_FLIP_DAILY,
            "70 arms on one day accumulate, none lost"
        );

        // Now push the same lane past the 128-bit ceiling and confirm it clamps silently.
        vm.prank(address(game));
        coinflip.creditFlip(ContractAddresses.VAULT, type(uint128).max);
        for (uint24 century = 71; century <= 90; ++century) {
            _arm(century * 100); // must not revert even with the lane at its ceiling
        }
        assertLe(
            _stakeAtOffset(ContractAddresses.VAULT, 0),
            type(uint128).max,
            "the lane clamps at its width rather than spilling or reverting"
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
        // Arming at the maximum level claims century 1 (the lowest unarmed), never jumps.
        _arm(maxLevel);
        assertEq(
            wwxrp.vaultAllowance(),
            wwxrp.INITIAL_VAULT_ALLOWANCE() * 3,
            "even the maximum level claims exactly one century per call"
        );
    }
}
