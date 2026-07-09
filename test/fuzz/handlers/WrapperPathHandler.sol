// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {DGNRS} from "../../../contracts/DGNRS.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";

interface IVaultOwnerCheck {
    function isVaultOwner(address account) external view returns (bool);
}

/// @title WrapperPathHandler — drives the DGNRS wrapper's own mutation paths so the
///        wrapper-backing invariants are exercised non-vacuously.
///
/// @notice The RedemptionHandler campaign proves burn/claim accounting but never MOVES the
///         wrapper: without wrapper actions, `invariant_wrapperBackingSufficient` holds on a
///         static pair (backing and supply both untouched), which is exactly the vacuity the
///         DGNRS-WRAPPER-BACKING-PROOF follow-up flags. This handler adds the wrapper's three
///         paired-decrement paths as fuzz actions:
///           - `unwrapTo` (vault owner): burns caller DGNRS + moves backing sDGNRS out — paired.
///           - `burnWrapped` (sDGNRS gambling path, active game): burns caller DGNRS via
///             burnForSdgnrs + burns the same amount of backing — paired.
///           - post-gameOver `DGNRS.burn`: burns caller DGNRS + deterministic-burns the same
///             amount of backing — paired.
///         plus the SOLE intentional equality break:
///           - `yearSweep` (365 days post-gameOver): burns ALL backing while DGNRS.totalSupply
///             stays untouched — the terminal charity forfeiture. Sets `ghost_yearSweepRan` so
///             the invariant can scope itself to the pre-sweep regime it is stated for.
///
/// @dev Vault-owner auth for `unwrapTo` is mocked (isVaultOwner(actor0) == true): the property
///      under test is the paired-decrement arithmetic, not DGVE governance. Actors are funded
///      with DGNRS from CREATOR's deploy-time 50B allocation (a plain ERC20 transfer). Actor
///      base 0xE0000 is disjoint from every existing handler (0xD0000 redemption, 0x60000 rng).
contract WrapperPathHandler is Test {
    sDGNRS public sdgnrs;
    DGNRS public dgnrs;
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    address[] public actors;
    address internal currentActor;

    // --- Ghost surface ---

    /// @notice Successful unwrapTo calls (wrapper + backing decremented together).
    uint256 public ghost_unwraps;

    /// @notice Successful active-game burnWrapped calls.
    uint256 public ghost_wrappedBurns;

    /// @notice Successful post-gameOver DGNRS.burn calls.
    uint256 public ghost_postGameOverBurns;

    /// @notice Latched true once yearSweep has executed — the sole intentional break of the
    ///         wrapper-backing equality. The invariants scope themselves on this flag.
    bool public ghost_yearSweepRan;

    /// @notice Cumulative sDGNRS totalSupply burned by wrapper-path actions (burnWrapped /
    ///         post-gameOver burn / yearSweep all burn backing supply). The RedemptionHandler's
    ///         INV-04 ghost ledger cannot see these — the supply-consistency invariant adds this
    ///         term so both handlers' burns reconcile against the live totalSupply.
    uint256 public ghost_sdgnrsBurnedViaWrapper;

    // --- Per-action coverage counters (surveillance) ---
    uint256 public calls_unwrapTo;
    uint256 public calls_burnWrapped;
    uint256 public calls_postGameOverBurn;
    uint256 public calls_yearSweep;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(sDGNRS sdgnrs_, DGNRS dgnrs_, DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        sdgnrs = sdgnrs_;
        dgnrs = dgnrs_;
        game = game_;
        vrf = vrf_;

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xE0000 + i));
            actors.push(actor);
            vm.deal(actor, 10 ether);
            // Fund with DGNRS from CREATOR's deploy-time allocation (plain ERC20 transfer).
            vm.prank(ContractAddresses.CREATOR);
            dgnrs.transfer(actor, 1_000_000 ether);
        }

        // Vault-owner auth is not the property under test — grant it to actor 0 only, by
        // exact-calldata mock, so unwrapTo's paired-decrement arithmetic is reachable.
        vm.mockCall(
            ContractAddresses.VAULT,
            abi.encodeWithSelector(IVaultOwnerCheck.isVaultOwner.selector, actors[0]),
            abi.encode(true)
        );
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =========================================================================
    // Action: unwrapTo — vault-owner DGNRS burn + backing sDGNRS transfer out
    // =========================================================================

    /// @notice Unwrap DGNRS to soulbound sDGNRS (actor 0 holds the mocked vault-owner bit).
    ///         Contract-side gate `!game.rngLocked()` may revert the call — fine either way;
    ///         the invariant re-checks the pair after every handler call.
    function tryUnwrapTo(uint256 amtSeed, uint256 recipSeed) external {
        calls_unwrapTo++;
        address owner_ = actors[0];
        uint256 bal = dgnrs.balanceOf(owner_);
        if (bal < 1 ether) return;
        uint256 amt = bound(amtSeed, 1 ether, bal);
        address recipient = actors[bound(recipSeed, 0, actors.length - 1)];
        vm.prank(owner_);
        try dgnrs.unwrapTo(recipient, amt) {
            ghost_unwraps++;
        } catch {}
    }

    // =========================================================================
    // Action: burnWrapped — active-game gambling burn through the wrapper
    // =========================================================================

    /// @notice Burn wrapped DGNRS via the sDGNRS gambling path. Subject to the full gambling
    ///         burn precondition set (min burn, prior-day resolution, rng not locked, game not
    ///         over) — attempts are cheap, successes are what pair-decrement the wrapper.
    function tryBurnWrapped(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_burnWrapped++;
        if (game.gameOver()) return;
        uint256 bal = dgnrs.balanceOf(currentActor);
        if (bal < 1 ether) return; // MIN_BURN floor
        uint256 amt = bound(amtSeed, 1 ether, bal);
        uint256 supplyBefore = sdgnrs.totalSupply();
        vm.prank(currentActor);
        try sdgnrs.burnWrapped(amt) {
            ghost_wrappedBurns++;
            ghost_sdgnrsBurnedViaWrapper += supplyBefore - sdgnrs.totalSupply();
        } catch {}
    }

    // =========================================================================
    // Action: post-gameOver DGNRS.burn — burn-through to ETH/stETH backing
    // =========================================================================

    /// @notice Burn DGNRS for proportional ETH/stETH once the game is over (the public
    ///         deterministic path). Paired: wrapper supply and sDGNRS backing fall together.
    function tryPostGameOverBurn(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_postGameOverBurn++;
        if (!game.gameOver()) return;
        uint256 bal = dgnrs.balanceOf(currentActor);
        if (bal == 0) return;
        uint256 amt = bound(amtSeed, 1, bal);
        uint256 supplyBefore = sdgnrs.totalSupply();
        vm.prank(currentActor);
        try dgnrs.burn(amt) {
            ghost_postGameOverBurns++;
            ghost_sdgnrsBurnedViaWrapper += supplyBefore - sdgnrs.totalSupply();
        } catch {}
    }

    // =========================================================================
    // Action: yearSweep — the sole intentional equality break, under warp
    // =========================================================================

    /// @notice Fire the terminal charity forfeiture: 365 days after gameOver, burn ALL
    ///         remaining backing 50-50 to GNRUS/VAULT. This is the ONE path allowed to leave
    ///         the wrapper under-backed; the ghost flag rescopes the invariants when it runs.
    function tryYearSweep() external {
        calls_yearSweep++;
        uint48 goTime = game.gameOverTimestamp();
        if (goTime == 0) return; // not game-over yet — sweep unreachable
        if (block.timestamp < uint256(goTime) + 365 days) {
            vm.warp(uint256(goTime) + 365 days + 1);
        }
        uint256 supplyBefore = sdgnrs.totalSupply();
        try dgnrs.yearSweep() {
            ghost_yearSweepRan = true;
            ghost_sdgnrsBurnedViaWrapper += supplyBefore - sdgnrs.totalSupply();
        } catch {}
    }
}
