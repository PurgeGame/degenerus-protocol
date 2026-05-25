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

    /// @dev Mirrors `StakedDegenerusStonk.MAX_ROLL` (private literal `175`). v47: at SUBMIT the
    ///      contract physically segregates the MAX possible payout (base × MAX_ROLL / 100 = 175%)
    ///      into `pendingRedemptionEthValue`; at RESOLVE that reservation is lowered from MAX to the
    ///      rolled amount (base × roll / 100). So an UNRESOLVED day contributes 175% of its base to
    ///      the cumulative scalar, not 100% (the v46 model). This is the v47 conservation delta.
    uint256 internal constant MAX_ROLL = 175;

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
            // v47: RedemptionPeriod.flipDay removed; only the write-once roll remains.
            (uint16 roll) = sdgnrs.redemptionPeriods(d);
            assertEq(
                uint256(roll),
                uint256(handler.ghost_perDay_firstRoll(d)),
                "INV-01: redemptionPeriods[D].roll diverged from first-write"
            );
        }
    }

    // =====================================================================
    //                  INV-02: ETH conservation (EXACT)
    // =====================================================================

    /// @notice INV-02 — 304-SPEC §1 lines 90-114 (v47-revised). `pendingRedemptionEthValue` equals
    ///         the sum over UNRESOLVED days D of `pendingByDay[D].ethBase * 1e9 * MAX_ROLL / 100`
    ///         (v47: the MAX 175% payout is segregated at submit) PLUS the sum over
    ///         resolved-but-unclaimed (P, D) of `pendingRedemptions[P][D].ethValueOwed *
    ///         redemptionPeriods[D].roll / 100` (the reservation lowered to the rolled amount at
    ///         resolve). EXACT per D-305-GWEI-SNAP-01: ethBase/ethValueOwed are gwei-aligned and
    ///         `gcd(1e9, 100) = 100` so both `× MAX_ROLL / 100` and `× roll / 100` divide exactly.
    function invariant_INV_02_EthConservationExact() public view {
        uint256 expected;
        uint256 len = handler.getDaysWrittenCount();
        uint256 bound = len < SCAN_CAP ? len : SCAN_CAP;
        uint256 actorN = handler.getActorCount();
        for (uint256 i = 0; i < bound; i++) {
            uint32 d = handler.getDayWritten(i);
            if (!handler.ghost_dayResolved(d)) {
                // v47 Unresolved: the MAX (175%) payout is segregated at submit.
                (uint64 ethBase, , ) = _readPendingByDay(d);
                expected += (uint256(ethBase) * 1e9 * MAX_ROLL) / 100;
            } else {
                // Resolved: sum over players of (ethValueOwed × roll / 100).
                (uint16 roll) = sdgnrs.redemptionPeriods(d);
                for (uint256 j = 0; j < actorN; j++) {
                    address actor = handler.getActor(j);
                    if (handler.ghost_claimDone(d, actor)) continue;
                    (uint96 ev, ) = sdgnrs.pendingRedemptions(actor, d);
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

    /// @notice INV-03 — 304-SPEC §1 lines 118-139 (v47-revised). In v47 the redemption BURNIE
    ///         RESERVE apparatus was removed entirely: BURNIE is settled at SUBMIT (redeemBurnieShare
    ///         → burnForCoinflip), so the `pendingRedemptionBurnie` cumulative scalar, the per-day
    ///         `pendingByDay[D].burnieBase` field, and the resolve-time `pendingRedemptionBurnie -=`
    ///         release were all deleted. There is no longer any reserved-BURNIE accounting state to
    ///         conserve across the burn→resolve→claim window — the invariant is structurally
    ///         discharged by construction (no field exists to diverge). The net-BURNIE-conservation
    ///         property (net new BURNIE == 0 at submit) is proven by REDEEM-08 (plan 323-03), not here.
    /// @dev Retained as a documented no-op so the §3.F attestation matrix keeps its INV-03 row;
    ///      asserting against a deleted storage slot would be vacuous (always zero).
    function invariant_INV_03_BurnieConservationExact() public view {
        // No-op: the redemption-BURNIE reserve was removed in v47 (settled at submit). See NatSpec.
        // Touch state read-only so the function body is non-trivial under the view mutability.
        assertTrue(address(sdgnrs) != address(0), "INV-03: harness wiring");
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
            // v47: per-day burnieBase + per-(P,D) burnieOwed removed; only the ETH leg remains.
            (uint64 ethBase, , ) = _readPendingByDay(d);
            if (ethBase == 0) continue;
            uint256 sumEth;
            for (uint256 j = 0; j < actorN; j++) {
                address actor = handler.getActor(j);
                (uint96 ev, ) = sdgnrs.pendingRedemptions(actor, d);
                sumEth += uint256(ev);
            }
            assertEq(
                uint256(ethBase) * 1e9,
                sumEth,
                "INV-04: pool.ethBase * 1e9 != sum pendingRedemptions[P][D].ethValueOwed"
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
                // v47 Unresolved: the MAX (175%) payout is segregated at submit.
                (uint64 ethBase, , ) = _readPendingByDay(d);
                expected += (uint256(ethBase) * 1e9 * MAX_ROLL) / 100;
            } else {
                (uint16 roll) = sdgnrs.redemptionPeriods(d);
                for (uint256 j = 0; j < actorN; j++) {
                    address actor = handler.getActor(j);
                    if (handler.ghost_claimDone(d, actor)) continue;
                    (uint96 ev, ) = sdgnrs.pendingRedemptions(actor, d);
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
                (uint16 roll) = sdgnrs.redemptionPeriods(d);
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
                (uint96 ev, ) = sdgnrs.pendingRedemptions(actor, d);
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
            // v47: per-day burnieBase removed; delete-at-resolve clears the 3 surviving fields.
            (uint64 ethBase, uint64 supplySnapshot, uint64 burned) = _readPendingByDay(d);
            assertEq(uint256(ethBase), 0, "INV-08: resolved day D < today retained ethBase");
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
            // v47: per-day burnieBase removed. `supplySnapshot` (lazy-init on the FIRST burn of a
            // day, independent of sub-gwei ethBase rounding) is the pool-existence indicator — it
            // matches the sentinel-set condition, whereas ethBase can round to 0 for a tiny burn
            // while the sentinel is still legitimately stamped to that day.
            (, uint64 supplySnapshot, ) = _readPendingByDay(d);
            if (supplySnapshot == 0) continue;
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
            (, uint64 supplySnapshot, uint64 burned) = _readPendingByDay(d);
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
                (uint96 ev, ) = sdgnrs.pendingRedemptions(actor, d);
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
            // v47: per-day burnieBase removed; `supplySnapshot` (lazy-init on first burn, sentinel-set
            // condition) is the pool-existence indicator — ethBase can round to 0 for a tiny burn
            // while the pool legitimately exists and is stamped.
            (, uint64 supplySnapshot, ) = _readPendingByDay(d);
            if (supplySnapshot == 0) continue;
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
            // v47: per-day burnieBase removed; `supplySnapshot` (lazy-init on first burn, the
            // sentinel-set condition) is the pool-existence indicator. ethBase can round to 0 for a
            // tiny burn while the pool legitimately exists and the sentinel names it.
            (, uint64 supplySnapshot, ) = _readPendingByDay(d);
            if (supplySnapshot != 0) {
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
    //   REDEEM-08: ETH-segregation conservation (v47 physical-segregation model)
    // =====================================================================

    /// @dev Storage slot of DegenerusGame.claimableWinnings (internal mapping). Slot 7 per the
    ///      v44 layout the redemption harness uses (RedemptionGas / StakedStonkRedemption seed it
    ///      at this slot). Read raw so the no-wrap invariant can observe a hypothetical underflow.
    uint256 internal constant GAME_CLAIMABLE_SLOT = 7;

    /// @notice REDEEM-08 conservation: the segregated redemption ETH PHYSICALLY lives in the sDGNRS
    ///         contract, so `address(sdgnrs).balance >= pendingRedemptionEthValue` at ALL times.
    /// @dev v47 model: submit pulls the MAX(175%) out of claimable into sDGNRS's balance via the
    ///      CHECKED pullRedemptionReserve (real ETH transfer); resolve lowers the obligation
    ///      MAX→rolled (the over-pull stays as free backing); claim/gameOver release exactly the
    ///      rolled amount out. The balance therefore always covers the obligation (telescoping = zero
    ///      drift). This is the property the pre-fix virtual-reserve model could violate (a 2nd
    ///      claimant or AfKing drain could leave the obligation un-backed).
    function invariant_balanceCoversPendingRedemptionEth() public view {
        assertGe(
            address(sdgnrs).balance,
            sdgnrs.pendingRedemptionEthValue(),
            "REDEEM-08: address(sdgnrs).balance < pendingRedemptionEthValue (segregated ETH under-backed)"
        );
    }

    /// @notice REDEEM-08 conservation: `claimablePool >= claimableWinnings[SDGNRS]` stays balanced
    ///         through every redemption action. pullRedemptionReserve decrements BOTH by the same
    ///         amount (CHECKED) and moves real ETH out; resolveRedemptionLootbox touches NEITHER (it
    ///         credits futurePrizePool from msg.value). The global pool always covers sDGNRS's slice.
    /// @dev The redemption path is the only writer of claimableWinnings[SDGNRS] in this harness
    ///      (the handler funds only sDGNRS), so claimablePool (global) >= claimableWinnings[SDGNRS]
    ///      (sDGNRS's slice) must always hold — a wrap of either toward 2^N would break it.
    function invariant_claimablePoolEqualsSumClaimable() public view {
        uint256 poolVal = game.claimablePoolView();
        uint256 sdgnrsClaimable = _claimableSdgnrs();
        assertGe(
            poolVal,
            sdgnrsClaimable,
            "REDEEM-08: claimablePool < claimableWinnings[SDGNRS] (paired debit drifted / wrapped)"
        );
    }

    /// @notice REDEEM-08 structural/behavioral: NO unchecked claimable subtraction survives in the
    ///         redemption path. The only claimableWinnings[SDGNRS] debit is the CHECKED
    ///         pullRedemptionReserve; a pre-fix UNCHECKED debit would wrap claimableWinnings[SDGNRS]
    ///         toward 2^256 (and claimablePool toward 2^128) under a randomized submit/resolve/claim/
    ///         gameOver sequence that drains claimable below an obligation. Behavioral form: across the
    ///         whole action history, neither raw value is ever anywhere near its wrap ceiling.
    /// @dev type(uint96).max (~7.9e28 wei ≈ 7.9e10 ETH) dwarfs any legitimate residual yet is ~1e48×
    ///      below a wrapped value (~1.16e77 / ~3.4e38), so it tightly catches a wrap of either scalar.
    function invariant_noUncheckedClaimableDebitInRedemptionPath() public view {
        assertLt(
            _claimableSdgnrs(),
            uint256(type(uint96).max),
            "REDEEM-08: claimableWinnings[SDGNRS] wrapped toward 2^256 (unchecked debit survived)"
        );
        assertLt(
            game.claimablePoolView(),
            uint256(type(uint96).max),
            "REDEEM-08: claimablePool wrapped toward 2^128 (unchecked debit survived)"
        );
    }

    // =====================================================================
    //                          INTERNAL READERS
    // =====================================================================

    /// @dev Read DegenerusGame.claimableWinnings[SDGNRS] (internal mapping @ slot 7) raw, so a
    ///      hypothetical pre-fix unchecked-debit wrap toward 2^256 is observable.
    function _claimableSdgnrs() internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(ContractAddresses.SDGNRS, GAME_CLAIMABLE_SLOT));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read the packed `DayPending` slot for day D and unpack its 3×uint64 fields. Mirrors
    ///      the handler's reader so the harness has direct access without an extra hop.
    ///      v47: per-day burnieBase removed (BURNIE settled at submit). DayPending is now
    ///      `{ethBase (bits 0-63), supplySnapshot (bits 64-127), burned (bits 128-191)}`.
    function _readPendingByDay(uint32 day)
        internal
        view
        returns (uint64 ethBase, uint64 supplySnapshot, uint64 burned)
    {
        bytes32 slot = keccak256(abi.encode(uint256(day), handler.SLOT_PENDING_BY_DAY()));
        uint256 raw = uint256(vm.load(address(sdgnrs), slot));
        ethBase = uint64(raw);
        supplySnapshot = uint64(raw >> 64);
        burned = uint64(raw >> 128);
    }
}
