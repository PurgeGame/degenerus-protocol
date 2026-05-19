// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RedemptionHandler} from "../fuzz/handlers/RedemptionHandler.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title RedemptionAccounting -- 13 invariant_INV_NN_* functions for v44 sStonk per-day source
/// @notice Mechanizes INV-01..12 from 304-SPEC §1 plus the v44.0 single-pool invariant INV-13
///         added at Phase 305 (D-305-SENTINEL-01). Every invariant asserts after every handler
///         action; EXACT-equality assertions on INV-02..05 are sound per D-305-GWEI-SNAP-01
///         (gcd(1e9, 100) = 100 → gwei-aligned × roll / 100 is exact for any integer roll).
/// @dev Run:
///        FOUNDRY_PROFILE=deep forge test --match-path "test/invariant/RedemptionAccounting.t.sol"
///      Slot constants for `vm.load` reads are re-exposed from `RedemptionHandler` (public
///      constants) so the harness uses a single source of truth for the v44 storage layout.
contract RedemptionAccounting is DeployProtocol {
    RedemptionHandler public handler;

    /// @dev Mirrors `StakedDegenerusStonk.MAX_DAILY_REDEMPTION_EV` (private literal `160 ether`).
    uint256 internal constant MAX_DAILY_REDEMPTION_EV = 160 ether;

    /// @dev Mirrors `StakedDegenerusStonk.MIN_BURN_AMOUNT` (private literal `1e18`).
    uint256 internal constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Hard cap on cross-day scan loops in invariant fns. Handler emits ≤ 256-call
    ///      sequences under FOUNDRY_PROFILE=deep so the bound is generously above expected.
    uint256 internal constant SCAN_CAP = 100;

    function setUp() public {
        _deployProtocol();
        // Warp 1 day past the deploy-pinned timestamp (matches RedemptionGas precedent so
        // currentDayView() advances off day 0).
        vm.warp(block.timestamp + 1 days);

        // Fund the game with ETH and credit sDGNRS via claimableWinnings + claimablePool so
        // burn paths see non-zero backing (RedemptionGas.t.sol precedent at :31-38).
        vm.deal(address(game), 100 ether);
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        vm.store(address(game), claimableSlot, bytes32(uint256(100 ether)));
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(100 ether) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1Val));

        // Construct the handler with 4 actors. The handler funds each from the Reward pool.
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, coin, 4);
        // Wire the coinflip mock so claim paths complete the full-payout branch.
        handler.setCoinflip(address(coinflip));

        // Register the 5 handler action selectors with Foundry's invariant fuzzer.
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = RedemptionHandler.action_burn.selector;
        selectors[1] = RedemptionHandler.action_advanceDay.selector;
        selectors[2] = RedemptionHandler.action_claim.selector;
        selectors[3] = RedemptionHandler.action_triggerGameOver.selector;
        selectors[4] = RedemptionHandler.action_burnOnPreviousDay.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    // =====================================================================
    //                  INV-01: Write-once roll immutability
    // =====================================================================

    /// @notice INV-01 — 304-SPEC §1 lines 78-86. For every D where the handler observed a
    ///         resolve, the on-chain `redemptionPeriods[D]` byte-equals the first-write value
    ///         the handler latched at that resolve. Mechanism: per-day mapping keying makes
    ///         the overwrite primitive physically unreachable (V-184 closure clause; ref
    ///         305-01-SUMMARY §"V-184 closure attestation").
    function invariant_INV_01_WriteOnceRoll() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (!handler.ghost_dayResolved(d)) continue;
            (uint16 roll, uint32 flipDay) = sdgnrs.redemptionPeriods(d);
            assertEq(
                uint256(roll),
                uint256(handler.ghost_perDay_firstRoll(d)),
                "INV-01: redemptionPeriods[D].roll diverged from first-write"
            );
            assertEq(
                uint256(flipDay),
                uint256(handler.ghost_perDay_firstFlipDay(d)),
                "INV-01: redemptionPeriods[D].flipDay diverged from first-write"
            );
        }
    }

    // =====================================================================
    //                  INV-02: ETH conservation (EXACT)
    // =====================================================================

    /// @notice INV-02 — 304-SPEC §1 lines 90-114. `pendingRedemptionEthValue` equals the
    ///         sum over unresolved days D of `pendingByDay[D].ethBase * 1e9` PLUS the sum
    ///         over resolved-but-unclaimed (P, D) of `pendingRedemptions[P][D].ethValueOwed
    ///         * redemptionPeriods[D].roll / 100`. EXACT equality per D-305-GWEI-SNAP-01:
    ///         ethValueOwed is gwei-aligned at source, and `gcd(1e9, 100) = 100` means every
    ///         downstream `× roll / 100` divides exactly. Tightens the SPEC's "dust-bounded"
    ///         framing to byte-identity post-refactor.
    function invariant_INV_02_EthConservationExact() public view {
        uint256 expected;
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (!handler.ghost_dayResolved(d)) {
                // Unresolved: ethBase × 1e9 contributes to the cumulative scalar.
                (uint64 ethBase, , , ) = _readPendingByDay(d);
                expected += uint256(ethBase) * 1e9;
            } else {
                // Resolved: sum over players of (ethValueOwed × roll / 100).
                (uint16 roll, ) = sdgnrs.redemptionPeriods(d);
                for (uint256 j = 0; j < actorN; j++) {
                    address actor = handler.getActor(j);
                    if (handler.ghost_claimDone(d, actor)) continue;
                    (uint96 ev, , ) = sdgnrs.pendingRedemptions(actor, d);
                    expected += (uint256(ev) * uint256(roll)) / 100;
                }
            }
        }
        assertEq(
            sdgnrs.pendingRedemptionEthValue(),
            expected,
            "INV-02: pendingRedemptionEthValue diverged from reconstructed sum"
        );
    }

    // =====================================================================
    //              INV-03: BURNIE conservation (EXACT)
    // =====================================================================

    /// @notice INV-03 — 304-SPEC §1 lines 118-139. BURNIE reservation is RELEASED at resolve
    ///         (sStonk:651 `pendingRedemptionBurnie -= burnieBase`), so the resolved-but-
    ///         unclaimed term is structurally zero. The cumulative-scalar invariant collapses
    ///         to: `pendingRedemptionBurnie == Σ over unresolved D of pendingByDay[D].burnieBase
    ///         × 1e9`. EXACT per D-305-GWEI-SNAP-01.
    function invariant_INV_03_BurnieConservationExact() public view {
        uint256 expected;
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (handler.ghost_dayResolved(d)) continue;
            (, uint64 burnieBase, , ) = _readPendingByDay(d);
            expected += uint256(burnieBase) * 1e9;
        }
        assertEq(
            _readPendingRedemptionBurnie(),
            expected,
            "INV-03: pendingRedemptionBurnie diverged from sum of unresolved pool burnieBase"
        );
    }

    // =====================================================================
    //              INV-04: Per-day base correctness (EXACT)
    // =====================================================================

    /// @notice INV-04 — 304-SPEC §1 lines 143-161. For every unresolved day D with non-empty
    ///         pool: `pendingByDay[D].ethBase × 1e9 == Σ over actors P of
    ///         pendingRedemptions[P][D].ethValueOwed`. EXACT.
    function invariant_INV_04_PerDayBaseCorrectness() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (handler.ghost_dayResolved(d)) continue;
            (uint64 ethBase, uint64 burnieBase, , ) = _readPendingByDay(d);
            if (ethBase == 0 && burnieBase == 0) continue;
            uint256 sumEth;
            uint256 sumBurnie;
            for (uint256 j = 0; j < actorN; j++) {
                address actor = handler.getActor(j);
                (uint96 ev, uint96 bv, ) = sdgnrs.pendingRedemptions(actor, d);
                sumEth += uint256(ev);
                sumBurnie += uint256(bv);
            }
            assertEq(
                uint256(ethBase) * 1e9,
                sumEth,
                "INV-04: pool.ethBase * 1e9 != sum pendingRedemptions[P][D].ethValueOwed"
            );
            assertEq(
                uint256(burnieBase) * 1e9,
                sumBurnie,
                "INV-04: pool.burnieBase * 1e9 != sum pendingRedemptions[P][D].burnieOwed"
            );
        }
    }

    // =====================================================================
    //          INV-05: Per-day cumulative correctness (EXACT)
    // =====================================================================

    /// @notice INV-05 — 304-SPEC §1 lines 165-187. Reorganization of INV-02 that asserts the
    ///         cumulative-vs-per-day-sum identity directly. Same expected value as INV-02
    ///         since both compute the same RHS; reproduced as a separate invariant fn so
    ///         §3.F attestation matrix has 13 distinct test_id rows to cite.
    function invariant_INV_05_PerDayCumulativeCorrectness() public view {
        uint256 expected;
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (!handler.ghost_dayResolved(d)) {
                (uint64 ethBase, , , ) = _readPendingByDay(d);
                expected += uint256(ethBase) * 1e9;
            } else {
                (uint16 roll, ) = sdgnrs.redemptionPeriods(d);
                for (uint256 j = 0; j < actorN; j++) {
                    address actor = handler.getActor(j);
                    if (handler.ghost_claimDone(d, actor)) continue;
                    (uint96 ev, , ) = sdgnrs.pendingRedemptions(actor, d);
                    expected += (uint256(ev) * uint256(roll)) / 100;
                }
            }
        }
        assertEq(
            sdgnrs.pendingRedemptionEthValue(),
            expected,
            "INV-05: cumulative scalar diverged from per-day reconstruction"
        );
    }

    // =====================================================================
    //          INV-06: No cross-player roll manipulation
    // =====================================================================

    /// @notice INV-06 — 304-SPEC §1 lines 191-199. For any (P, D) where the handler observed
    ///         P had a claim and D resolved, `redemptionPeriods[D].roll` byte-equals
    ///         `ghost_perDay_firstRoll[D]`. Subsumed by INV-01; included as a separate row so
    ///         §3.F attestation cites it directly. The 304-SPEC §1 model factors INV-01 as
    ///         "post-write immutability" and INV-06 as "no rogue writer in the burn-to-claim
    ///         window" — INV-01 transitively covers both because the writer set is exactly
    ///         `resolveRedemptionPeriod` (onlyGame, called via advance) and the per-day key
    ///         ensures that writer can never target an already-resolved day.
    function invariant_INV_06_NoCrossPlayerRollManipulation() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (!handler.ghost_dayResolved(d)) continue;
            for (uint256 j = 0; j < actorN; j++) {
                address actor = handler.getActor(j);
                if (handler.ghost_perDay_perPlayer_ethValueOwed(d, actor) == 0) continue;
                (uint16 roll, ) = sdgnrs.redemptionPeriods(d);
                assertEq(
                    uint256(roll),
                    uint256(handler.ghost_perDay_firstRoll(d)),
                    "INV-06: roll changed across actors after first write"
                );
            }
        }
    }

    // =====================================================================
    //          INV-07: No self-roll manipulation via timing
    // =====================================================================

    /// @notice INV-07 — 304-SPEC §1 lines 203-217. For every (P, D) where the handler latched
    ///         a locked snapshot (last burn of the day) and the claim is not yet done,
    ///         on-chain `pendingRedemptions[P][D].ethValueOwed` byte-equals the snapshot.
    ///         Mechanism: composite-key (`pendingRedemptions[P][D]`) means burns by P on a
    ///         DIFFERENT day write a DIFFERENT slot; burns by Q != P on day D write Q's slot;
    ///         resolves write `redemptionPeriods[D]`, NOT `pendingRedemptions[P][D]`. V-184
    ///         closure for the per-player vector.
    function invariant_INV_07_NoSelfRollManipulation() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            for (uint256 j = 0; j < actorN; j++) {
                address actor = handler.getActor(j);
                uint96 locked = handler.ghost_perPlayer_locked_ethValueOwed(d, actor);
                if (locked == 0) continue;
                if (handler.ghost_claimDone(d, actor)) continue;
                (uint96 ev, , ) = sdgnrs.pendingRedemptions(actor, d);
                assertEq(
                    uint256(ev),
                    uint256(locked),
                    "INV-07: pendingRedemptions[P][D].ethValueOwed mutated post-finalization"
                );
            }
        }
    }

    // =====================================================================
    //          INV-08: Pre-advance-gap burn safety
    // =====================================================================

    /// @notice INV-08 — 304-SPEC §1 lines 221-229. After a resolve of day D' the contract
    ///         deletes `pendingByDay[D']` per SPEC-04 (c); the slot reads zero on all four
    ///         fields. Exercised structurally by action_burnOnPreviousDay (the sentinel
    ///         exerciser); INV-13 subsumes the cross-day pool-aliasing concern.
    function invariant_INV_08_PreAdvanceGapBurnSafety() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint32 today = game.currentDayView();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (d >= today) continue;
            if (!handler.ghost_dayResolved(d)) continue;
            (uint64 ethBase, uint64 burnieBase, uint64 supplySnapshot, uint64 burned) = _readPendingByDay(d);
            assertEq(uint256(ethBase), 0, "INV-08: resolved day D < today retained ethBase");
            assertEq(uint256(burnieBase), 0, "INV-08: resolved day D < today retained burnieBase");
            assertEq(uint256(supplySnapshot), 0, "INV-08: resolved day D < today retained supplySnapshot");
            assertEq(uint256(burned), 0, "INV-08: resolved day D < today retained burned");
        }
    }

    // =====================================================================
    //          INV-09: Skipped-advance recovery (sentinel-trivialized)
    // =====================================================================

    /// @notice INV-09 — 304-SPEC §1 lines 233-241. Per D-305-SENTINEL-01 / INV-13, at most
    ///         one day's pool may be unresolved at any time. The sentinel `pendingResolveDay`
    ///         always names that day exactly, so "oldest-first ordering" collapses to "the
    ///         only ordering." Assertion: every observed day D in history with non-zero
    ///         pendingByDay[D].ethBase satisfies D == pendingResolveDay (or D >= today, which
    ///         means today's accumulation is still ongoing).
    function invariant_INV_09_SkippedAdvanceRecovery() public view {
        uint32 stamp = sdgnrs.pendingResolveDay();
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            (uint64 ethBase, uint64 burnieBase, , ) = _readPendingByDay(d);
            if (ethBase == 0 && burnieBase == 0) continue;
            // A non-empty pool MUST be the stamped day under the single-pool invariant.
            assertEq(
                uint256(d),
                uint256(stamp),
                "INV-09: non-empty pendingByDay[D] for D != pendingResolveDay"
            );
        }
    }

    // =====================================================================
    //                  INV-10: Per-day supply cap
    // =====================================================================

    /// @notice INV-10 — 304-SPEC §1 lines 245-259. `pendingByDay[D].burned ≤
    ///         pendingByDay[D].supplySnapshot / 2`. Pool fields are in whole-token units
    ///         (D-305-STRUCT-TIGHTEN-01), so the comparison is direct (no 1e18 scaling needed).
    function invariant_INV_10_PerDaySupplyCap() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            (, , uint64 supplySnapshot, uint64 burned) = _readPendingByDay(d);
            if (supplySnapshot == 0) continue;
            assertLe(
                uint256(burned),
                uint256(supplySnapshot) / 2,
                "INV-10: pendingByDay[D].burned exceeds half of supplySnapshot"
            );
        }
    }

    // =====================================================================
    //              INV-11: Per-(player, day) EV cap
    // =====================================================================

    /// @notice INV-11 — 304-SPEC §1 lines 263-277. For every (P, D): `pendingRedemptions[P][D]
    ///         .ethValueOwed ≤ MAX_DAILY_REDEMPTION_EV` (160 ether). Composite-key resets the
    ///         cap on each new day.
    function invariant_INV_11_PerPlayerPerDayEvCap() public view {
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            for (uint256 j = 0; j < actorN; j++) {
                address actor = handler.getActor(j);
                (uint96 ev, , ) = sdgnrs.pendingRedemptions(actor, d);
                if (ev == 0) continue;
                assertLe(
                    uint256(ev),
                    MAX_DAILY_REDEMPTION_EV,
                    "INV-11: pendingRedemptions[P][D].ethValueOwed exceeds MAX_DAILY_REDEMPTION_EV"
                );
            }
        }
    }

    // =====================================================================
    //              INV-12: gameOver mid-pending safety
    // =====================================================================

    /// @notice INV-12 — 304-SPEC §1 lines 281-296. Per SPEC-04 (a) gracefully-resolve lock, the
    ///         post-gameOver advance still fires `resolveRedemptionPeriod` for pre-gameOver
    ///         pending days. Once `gameOver == true`, any pending non-zero pool MUST be named
    ///         by `pendingResolveDay` (the eventual advance can recover it; no orphan exists).
    function invariant_INV_12_GameOverMidPending() public view {
        if (!game.gameOver()) return;
        uint32 stamp = sdgnrs.pendingResolveDay();
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (handler.ghost_dayResolved(d)) continue;
            (uint64 ethBase, uint64 burnieBase, , ) = _readPendingByDay(d);
            if (ethBase == 0 && burnieBase == 0) continue;
            assertEq(
                uint256(d),
                uint256(stamp),
                "INV-12: orphan non-empty pool exists post-gameOver (no sentinel match)"
            );
        }
    }

    // =====================================================================
    //              INV-13: Single-pool pending (v44.0 closure)
    // =====================================================================

    /// @notice INV-13 — 305-01-SUMMARY D-305-SENTINEL-01. At any reachable state, at most one
    ///         day's `pendingByDay[D]` is non-empty. If exactly one, that D MUST equal
    ///         `sdgnrs.pendingResolveDay()`. If zero, `pendingResolveDay()` MUST be 0.
    ///         Structural mechanism: `_submitGamblingClaimFrom` reverts `PriorDayUnresolved`
    ///         when `pendingResolveDay != 0 && pendingResolveDay != currentDay`. Load-bearing
    ///         v44.0 closure assertion alongside INV-01.
    function invariant_INV_13_SinglePoolPending() public view {
        uint32 stamp = sdgnrs.pendingResolveDay();
        uint256 nonEmptyCount;
        uint32 nonEmptyDay;
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            (uint64 ethBase, uint64 burnieBase, , ) = _readPendingByDay(d);
            if (ethBase != 0 || burnieBase != 0) {
                nonEmptyCount++;
                nonEmptyDay = d;
            }
        }
        assertLe(nonEmptyCount, 1, "INV-13: more than one pendingByDay[D] non-empty simultaneously");
        if (nonEmptyCount == 1) {
            assertEq(
                uint256(nonEmptyDay),
                uint256(stamp),
                "INV-13: non-empty pendingByDay[D] does not match pendingResolveDay sentinel"
            );
        } else {
            assertEq(
                uint256(stamp),
                0,
                "INV-13: pendingResolveDay non-zero but no pendingByDay is non-empty"
            );
        }
    }

    // =====================================================================
    //                          INTERNAL READERS
    // =====================================================================

    /// @dev Read the packed `DayPending` slot for day D and unpack its 4×uint64 fields. Mirrors
    ///      the handler's reader so the harness has direct access without an extra hop.
    function _readPendingByDay(uint32 day)
        internal
        view
        returns (uint64 ethBase, uint64 burnieBase, uint64 supplySnapshot, uint64 burned)
    {
        bytes32 slot = keccak256(abi.encode(uint256(day), handler.SLOT_PENDING_BY_DAY()));
        uint256 raw = uint256(vm.load(address(sdgnrs), slot));
        ethBase = uint64(raw);
        burnieBase = uint64(raw >> 64);
        supplySnapshot = uint64(raw >> 128);
        burned = uint64(raw >> 192);
    }

    /// @dev Read the internal `pendingRedemptionBurnie` cumulative scalar via slot derivation.
    function _readPendingRedemptionBurnie() internal view returns (uint256) {
        return uint256(vm.load(address(sdgnrs), bytes32(handler.SLOT_PENDING_REDEMPTION_BURNIE())));
    }
}
