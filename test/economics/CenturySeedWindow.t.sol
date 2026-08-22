// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CenturySeedWindow — the permissionless x00 re-seed of the deploy FLIP window.
///
/// @notice `armCenturySeed()` re-arms the deploy-time seed — SEED_FLIP_DAILY per day for
///         SEED_FLIP_DAYS days, to VAULT and to sDGNRS — once per x00 level. It is
///         deliberately OFF the advance path, so these tests drive it directly and mock the
///         game's `purchaseInfo()` to place the level and the RNG lock.
///
///         The properties that matter, and why each has teeth:
///         - SEED-01 it is not callable below level 100 (nothing to re-seed yet).
///         - SEED-02 arming credits exactly SEED_FLIP_DAILY on each of the 20 days, to both
///           recipients, starting at the next unresolved day.
///         - SEED-03 it is one-shot per century: the second call reverts.
///         - SEED-04 it ADDS to a day's existing stake rather than replacing it. This is the
///           one with real teeth: `_setFlipStake` is a masked overwrite, and sDGNRS is on
///           perpetual auto-rebuy by level 100, so a replace would silently destroy a stake
///           the protocol had already rolled forward.
///         - SEED-05 a later century re-opens it.
///         - SEED-06 it is refused while the RNG is locked, so a seed can never be aimed at a
///           day whose word is already committed.
///         - SEED-07 the vault's WWXRP reserve doubles each century off the deploy allowance,
///           and lands in the uncirculated allowance rather than a balance.
contract CenturySeedWindow is DeployProtocol {
    uint256 internal constant SEED_FLIP_DAILY = 200_000 ether;
    uint24 internal constant SEED_FLIP_DAYS = 20;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// @dev Place the game at `lvl` with the RNG lock in the given state. `armCenturySeed`
    ///      reads level and lock from this one call, so mocking it is the whole surface.
    function _setLevel(uint24 lvl, bool rngLocked_) internal {
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(IDegenerusGame.purchaseInfo.selector),
            abi.encode(lvl, false, false, rngLocked_, uint256(0.01 ether))
        );
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
    // SEED-01 / SEED-03 / SEED-05 / SEED-06 — the gate
    // ------------------------------------------------------------------

    function testNotArmableBelowFirstCentury() public {
        _setLevel(99, false);
        vm.expectRevert(Coinflip.SeedNotDue.selector);
        coinflip.armCenturySeed();
    }

    function testArmsOncePerCentury() public {
        _setLevel(100, false);
        coinflip.armCenturySeed();

        // Same century, whatever the level does inside it: already spent.
        vm.expectRevert(Coinflip.SeedNotDue.selector);
        coinflip.armCenturySeed();

        _setLevel(150, false);
        vm.expectRevert(Coinflip.SeedNotDue.selector);
        coinflip.armCenturySeed();
    }

    function testStaysArmableUntilUsed() public {
        // Opened at level 100 but nobody called; still available deep into the century.
        uint256 before = _stakeAtOffset(ContractAddresses.VAULT, 0);
        _setLevel(187, false);
        coinflip.armCenturySeed();
        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, 0) - before,
            SEED_FLIP_DAILY,
            "a late call still seeds the window"
        );
    }

    function testNextCenturyReopens() public {
        uint256 before = _stakeAtOffset(ContractAddresses.VAULT, 0);

        _setLevel(100, false);
        coinflip.armCenturySeed();

        _setLevel(200, false);
        coinflip.armCenturySeed();
        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, 0) - before,
            2 * SEED_FLIP_DAILY,
            "second century stacks onto the first window's overlapping day"
        );
    }

    /// @dev The catch-up property, and the one the earlier suite missed: arriving late enough
    ///      to have skipped a whole century must claim the SKIPPED one first, not jump to the
    ///      current one. A jump would silently forfeit century 1's window and its WWXRP leg.
    function testLateFirstCallClaimsTheSkippedCenturyNotTheCurrentOne() public {
        uint256 deployAllowance = wwxrp.INITIAL_VAULT_ALLOWANCE();
        uint256 before = wwxrp.vaultAllowance();

        // Nothing armed, and we are already deep into century 2.
        _setLevel(250, false);
        coinflip.armCenturySeed();
        assertEq(
            wwxrp.vaultAllowance() - before,
            2 * deployAllowance,
            "first call claims century 1 and pays century 1's figure, not century 2's"
        );

        // The second call picks up century 2, still at the same level.
        coinflip.armCenturySeed();
        assertEq(
            wwxrp.vaultAllowance() - before,
            6 * deployAllowance,
            "second call claims century 2 (2B + 4B cumulative)"
        );

        // Century 3 is not due at level 250.
        vm.expectRevert(Coinflip.SeedNotDue.selector);
        coinflip.armCenturySeed();
    }

    function testRefusedWhileRngLocked() public {
        _setLevel(100, true);
        vm.expectRevert(Coinflip.RngLocked.selector);
        coinflip.armCenturySeed();

        // And the latch did not burn: it is still armable once the lock clears.
        _setLevel(100, false);
        coinflip.armCenturySeed();
    }

    // ------------------------------------------------------------------
    // SEED-02 — the window it actually writes
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

        _setLevel(100, false);
        coinflip.armCenturySeed();

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

        // The day after the window closes is untouched.
        assertEq(
            _stakeAtOffset(ContractAddresses.VAULT, SEED_FLIP_DAYS),
            vaultBefore[SEED_FLIP_DAYS],
            "the window stops at SEED_FLIP_DAYS"
        );
    }

    // ------------------------------------------------------------------
    // SEED-04 — the one with teeth: add, never replace
    // ------------------------------------------------------------------

    function testAddsToAnExistingStakeInsteadOfReplacingIt() public {
        // Give sDGNRS a standing stake on the window's first day, the way auto-rebuy
        // would have. creditFlip is the game-only rail that rolls credit onto the next day.
        uint256 standing = 12_345 ether;
        vm.prank(address(game));
        coinflip.creditFlip(ContractAddresses.SDGNRS, standing);

        uint256 before = _stakeAtOffset(ContractAddresses.SDGNRS, 0);
        assertGt(before, 0, "non-vacuous: sDGNRS holds a stake before arming");

        _setLevel(100, false);
        coinflip.armCenturySeed();

        assertEq(
            _stakeAtOffset(ContractAddresses.SDGNRS, 0),
            before + SEED_FLIP_DAILY,
            "the seed adds to the standing stake; a masked overwrite would have destroyed it"
        );
    }

    // ------------------------------------------------------------------
    // SEED-07 — the vault WWXRP reserve doubles off the deploy allowance
    // ------------------------------------------------------------------

    /// @dev The doubling is stated against WWXRP's deploy allowance, which Coinflip mirrors
    ///      as a local constant. Pin the equality so the two cannot drift apart silently.
    function testWwxrpSeedConstantMatchesDeployAllowance() public view {
        assertEq(
            wwxrp.INITIAL_VAULT_ALLOWANCE(),
            1_000_000_000 ether,
            "Coinflip's mirrored WWXRP_VAULT_SEED must equal WWXRP.INITIAL_VAULT_ALLOWANCE"
        );
    }

    function testVaultWwxrpDoublesEachArm() public {
        // The deploy allowance is the first payment; the first arm pays double it.
        uint256 deployAllowance = wwxrp.INITIAL_VAULT_ALLOWANCE();
        assertEq(wwxrp.vaultAllowance(), deployAllowance, "starts at the deploy reserve");

        _setLevel(100, false);
        coinflip.armCenturySeed();
        assertEq(
            wwxrp.vaultAllowance() - deployAllowance,
            2 * deployAllowance,
            "century 1 pays double the deploy reserve"
        );

        uint256 afterFirst = wwxrp.vaultAllowance();
        _setLevel(200, false);
        coinflip.armCenturySeed();
        assertEq(
            wwxrp.vaultAllowance() - afterFirst,
            4 * deployAllowance,
            "century 2 pays double again"
        );
    }

    /// @dev It lands in the uncirculated allowance, not a balance: WWXRP._mint intercepts
    ///      VAULT-destined mints. A balance credit would put it straight into circulation.
    function testVaultWwxrpLandsInAllowanceNotBalance() public {
        uint256 balBefore = wwxrp.balanceOf(ContractAddresses.VAULT);
        uint256 supplyBefore = wwxrp.totalSupply();

        _setLevel(100, false);
        coinflip.armCenturySeed();

        assertEq(wwxrp.balanceOf(ContractAddresses.VAULT), balBefore, "no balance credited");
        assertEq(wwxrp.totalSupply(), supplyBefore, "totalSupply untouched: allowance is uncirculated");
    }

    /// @dev Production cost: at an x00 level the seeded days are far past the deploy window,
    ///      so all twenty slots per recipient are virgin (cold zero -> nonzero).
    function testArmGasOnVirginDays() public {
        vm.warp(vm.getBlockTimestamp() + 40 days);
        _setLevel(100, false);
        uint256 g0 = gasleft();
        coinflip.armCenturySeed();
        uint256 used = g0 - gasleft();
        emit log_named_uint("armCenturySeed_gas_virgin_days", used);
        // Ceiling guard, not a target: twenty cold slots per recipient plus the per-day
        // events. It matters because it is the figure any decision to fold this into
        // another transaction has to budget for.
        assertLt(used, 800_000, "century seed arm stays a sub-800k standalone transaction");
    }
}
