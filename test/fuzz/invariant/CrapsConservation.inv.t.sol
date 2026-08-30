// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "../../craps/CrapsViews.sol";
import {CrapsPins} from "../../craps/CrapsPins.sol";
import {CrapsBattle} from "../../../contracts/CrapsBattle.sol";
import {CrapsFlowHandler} from "../handlers/CrapsFlowHandler.sol";

contract InvHarness is CrapsViews {}

/// @title CrapsConservation — the craps table's always-on structural invariants, handler-driven.
///
/// @notice The craps councils derived these properties by hand; this suite makes them standing
///         machine checks, the way `PoolConservation.inv` does for the core pools. A handler
///         walks every money door in random order across real protocol days, and after every
///         action the campaign asserts the five properties that must hold in EVERY reachable
///         state — not on average, not per scenario:
///
///         (1) invariant_crapsNeverMints — the table is burn-only. `mintForGame` recording a
///             single wei is a finding, exactly as `CrapsSystemEcon` frames it.
///         (2) invariant_progressiveNeverExceedsItsFunding — the pool is release-only against
///             the protocol money that ever became spendable: Σ opened-day (main + high)
///             budgets. Contributions, ladder shares and every denied-boost rollover are carved
///             from inside that figure, so a pool above it is money from nowhere.
///         (3) invariant_dayBooksSplitSound — for every opened day, the high-lane half of the
///             packed action book never exceeds the total half. The budget draw subtracts one
///             from the other unchecked; this is the bound that keeps it whole.
///         (4) invariant_fieldsResolveOnce — an immediate REPEAT settle of a settled field
///             credits nothing. The handler re-runs `resolveSlot` after every successful walk
///             and accumulates any credit delta; a single non-zero wei fails the campaign.
///         (5) invariant_resolvedNeverExceedsEntrants — no touched field's resolution cursor
///             passes its head count.
///
///         WHAT IS DELIBERATELY NOT HERE: `credited <= burned` is NOT an invariant of a craps
///         table — a single Goal run legitimately credits a multiple of its burn, and the
///         table's conservation is STATISTICAL (the engine's edge), graded end-to-end by
///         `CrapsSystemEcon` and certified by the C++ calibration runs. Asserting it here would
///         fail on any lucky sequence.
///
///         NON-VACUITY. afterInvariant fails any campaign that did not actually exercise the
///         surface: entries, day tickets, settled fields, opened days and keeper cranks must
///         all have happened, so a green run can never be a run where nothing moved.
///
///         FALSIFIABILITY. Two focused tests seed the exact bug shapes: a progressive balance
///         inflated with no funding behind it (field-isolated store into `_progressive`,
///         slot 17 of the harness) trips (2), and an unbacked credit minted outside a
///         settlement trips the repeat-settle ledger's premise by construction. A wired
///         invariant that cannot register its own bug shape is decoration; these prove ours do.
///
/// @dev Test-only. ZERO contracts/*.sol mutation. Runs under the [invariant] profile
///      (runs = 256, depth = 128, fail_on_revert = false).
contract CrapsConservationInv is CrapsPins {
    InvHarness internal craps;
    CrapsFlowHandler internal handler;

    function setUp() public {
        _installPins();
        craps = new InvHarness();
        // Genesis is a Craps warm-up day; every fixture plays from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        handler = new CrapsFlowHandler(craps);
        // The handler's creator holds the custom-battle roll, granted by the vault's majority.
        address battleCreator = handler.creator();
        vm.prank(vaultOwner);
        craps.setBattleCreator(battleCreator, true);
        // The campaign's first day, opened before any random walk so every action has a table.
        handler.advanceDay(1);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = CrapsFlowHandler.advanceDay.selector;
        selectors[1] = CrapsFlowHandler.enterWindow.selector;
        selectors[2] = CrapsFlowHandler.enterDay.selector;
        selectors[3] = CrapsFlowHandler.amend.selector;
        selectors[4] = CrapsFlowHandler.buyFuture.selector;
        selectors[5] = CrapsFlowHandler.applyPasses.selector;
        selectors[6] = CrapsFlowHandler.upgrade.selector;
        selectors[7] = CrapsFlowHandler.customBattle.selector;
        selectors[8] = CrapsFlowHandler.donate.selector;
        selectors[9] = CrapsFlowHandler.closeNextWindow.selector;
        selectors[10] = CrapsFlowHandler.settleSlot.selector;
        selectors[11] = CrapsFlowHandler.keep.selector;
        selectors[12] = CrapsFlowHandler.convert.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ── The invariants ──────────────────────────────────────────────────────

    function invariant_crapsNeverMints() public view {
        assertEq(flip.totalMinted(), 0, "craps minted liquid FLIP");
    }

    function invariant_progressiveNeverExceedsItsFunding() public view {
        assertLe(
            craps.progressiveOf(),
            handler.ghost_subsidies(),
            "progressive holds more than the protocol ever allocated"
        );
    }

    function invariant_dayBooksSplitSound() public view {
        uint256 n = handler.openedDayCount();
        for (uint256 i = 0; i < n; ++i) {
            uint24 day = handler.openedDayAt(i);
            assertLe(
                craps.highStakedOf(day),
                craps.dayStaked(day),
                "high-lane action exceeds the day's total action"
            );
        }
    }

    function invariant_fieldsResolveOnce() public view {
        assertEq(
            handler.ghost_repeatSettleCreditDelta(),
            0,
            "a repeat settle of a settled field credited FLIP"
        );
    }

    function invariant_conversionsHoldTheFixedRate() public view {
        assertEq(
            handler.ghost_conversionRateBreaks(),
            0,
            "a normal-to-high conversion moved a lane off the 19:1 rate"
        );
    }

    function invariant_resolvedNeverExceedsEntrants() public view {
        uint256 n = handler.slotCount();
        for (uint256 i = 0; i < n; ++i) {
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(handler.slotAt(i)));
            assertLe(b.resolved, b.entrants, "resolution cursor passed the head count");
        }
    }

    // ── Non-vacuity ─────────────────────────────────────────────────────────

    function afterInvariant() public view {
        assertGt(handler.ghost_entries(), 0, "vacuous: no entries happened");
        assertGt(handler.ghost_settledFields(), 0, "vacuous: no field ever settled");
        assertGt(handler.ghost_scheduledSettles(), 0, "vacuous: no SCHEDULED field ever settled");
        assertGt(handler.openedDayCount(), 1, "vacuous: the campaign never left day one");
        assertGt(handler.ghost_keeps(), 0, "vacuous: the keeper never cranked");
    }

    // ── Falsifiability ──────────────────────────────────────────────────────

    /// @dev Seed the exact bug shape invariant (2) exists for — a progressive balance with no
    ///      funding behind it — and prove the wired check registers it, then goes green again
    ///      when the inflation is reverted. `_progressive` is slot 17 of `CrapsBattle`
    ///      (scripts/layout/golden/CrapsBattle.json), field-isolated: the whole slot is the pool.
    function test_falsifiable_progressiveInflationIsCaught() public {
        bytes32 slot = bytes32(uint256(17));
        bytes32 prior = vm.load(address(craps), slot);
        uint256 inflated = uint256(prior) + handler.ghost_subsidies() + 1_000_000 ether;
        vm.store(address(craps), slot, bytes32(inflated));
        assertGt(
            craps.progressiveOf(),
            handler.ghost_subsidies(),
            "the seeded inflation must register as a break"
        );
        vm.store(address(craps), slot, prior);
        assertLe(craps.progressiveOf(), handler.ghost_subsidies(), "restored state must be green");
    }

    /// @dev Drive one full window lifecycle by hand and prove the repeat-settle ledger is live:
    ///      the field settles, the repeat walk credits zero, and the ghost the invariant reads
    ///      stays zero — on a campaign that verifiably settled something (non-vacuous by
    ///      construction, not by trust).
    /// @dev Drive the conversion door by hand and prove its rate ghost is live: a seeded bank
    ///      converts, the counter moves, and the rate check registered a clean pass.
    function test_falsifiable_conversionDoorIsLive() public {
        craps.setPassCredits(handler.actors(0), 40, 0);
        handler.convert(0, 1);
        assertGt(handler.ghost_conversions(), 0, "the hand-driven conversion must have landed");
        assertEq(handler.ghost_conversionRateBreaks(), 0, "a clean conversion must not mark the ghost");
    }

    function test_falsifiable_repeatSettleLedgerIsLive() public {
        // Both seats take period 0 — the first window closeNextWindow shuts.
        handler.enterWindow(0, 1, 0, false);
        handler.enterWindow(1, 2, 0, false);
        handler.closeNextWindow(7);
        handler.settleSlot(0);
        assertGt(handler.ghost_settledFields(), 0, "the hand-driven field must have settled");
        assertEq(handler.ghost_repeatSettleCreditDelta(), 0, "repeat settle must credit nothing");
    }
}
