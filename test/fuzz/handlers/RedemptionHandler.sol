// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakedDegenerusStonk} from "../../../contracts/StakedDegenerusStonk.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";

/// @title RedemptionHandler -- Handler for gambling burn lifecycle invariant tests
/// @notice Wraps the burn-resolve-claim lifecycle with ghost variable tracking,
///         multi-actor support, and bounded inputs for the Foundry invariant fuzzer.
/// @dev Drives state exploration for all 7 redemption invariants. Actors are seeded
///      with sDGNRS from the Reward pool and ETH for gas.
contract RedemptionHandler is Test {
    StakedDegenerusStonk public sdgnrs;
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    BurnieCoin public coin;

    // =========================================================================
    //                          GHOST VARIABLES
    // =========================================================================

    uint256 public ghost_totalBurned;            // cumulative sDGNRS burned
    uint256 public ghost_totalEthClaimed;        // cumulative ETH received from claims
    uint256 public ghost_totalBurnieClaimed;     // cumulative BURNIE received from claims
    uint256 public ghost_periodsResolved;        // count of resolved periods
    uint256 public ghost_claimCount;             // successful claim calls
    uint256 public ghost_lastPeriodIndex;        // last seen redemptionPeriodIndex
    uint256 public ghost_periodIndexDecreased;   // counter: incremented if period index ever decreases
    uint256 public ghost_rollOutOfBounds;        // counter: incremented if roll outside [25,175]
    uint256 public ghost_supplyBurnMismatch;     // counter: incremented if supply accounting is off
    uint256 public ghost_initialSupply;          // totalSupply at construction time
    uint256 public ghost_doubleClaim;            // counter: incremented if re-claim succeeds
    uint256 public ghost_totalEthDirect;         // cumulative ethDirect from RedemptionClaimed events
    uint256 public ghost_totalLootboxEth;        // cumulative lootboxEth from RedemptionClaimed events
    uint256 public ghost_totalRolledEth;         // cumulative totalRolledEth (ethDirect + lootboxEth per claim)

    // =========================================================================
    //                          CALL COUNTERS
    // =========================================================================

    uint256 public calls_burn;
    uint256 public calls_advanceDay;
    uint256 public calls_claim;
    uint256 public calls_triggerGameOver;

    // =========================================================================
    //                          ACTOR MANAGEMENT
    // =========================================================================

    address[] public actors;
    address internal currentActor;
    uint256 public actorCount;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    // =========================================================================
    //                       STORAGE SLOT CONSTANTS
    // =========================================================================

    uint256 private constant SLOT_PENDING_BURNIE = 10;
    uint256 private constant SLOT_PERIOD_INDEX = 14;
    uint256 private constant SLOT_PERIOD_BURNED = 15;
    uint256 private constant SLOT_SUPPLY_SNAPSHOT = 13;

    // =========================================================================
    //                          CONSTRUCTOR
    // =========================================================================

    constructor(
        StakedDegenerusStonk sdgnrs_,
        DegenerusGame game_,
        MockVRFCoordinator vrf_,
        BurnieCoin coin_,
        uint256 numActors
    ) {
        sdgnrs = sdgnrs_;
        game = game_;
        vrf = vrf_;
        coin = coin_;

        ghost_initialSupply = sdgnrs.totalSupply();

        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xD0000 + i));
            actors.push(actor);
            vm.deal(actor, 10 ether);

            // Give each actor sDGNRS from the Reward pool
            vm.prank(address(game_));
            sdgnrs_.transferFromPool(StakedDegenerusStonk.Pool.Reward, actor, 1_000_000 ether);
        }
        actorCount = numActors;
    }

    // =========================================================================
    //                        ACTION: BURN
    // =========================================================================

    /// @notice Burn sDGNRS for a random actor with bounded amount
    /// @param actorSeed Seed for actor selection
    /// @param amount Raw burn amount, bounded to actor's balance
    function action_burn(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        calls_burn++;

        // Early return if game is over or RNG is locked
        if (game.gameOver()) return;
        if (game.rngLocked()) return;

        // Get actor balance, early return if zero
        uint256 bal = sdgnrs.balanceOf(currentActor);
        if (bal == 0) return;

        // Bound amount to [1, bal]
        amount = bound(amount, 1, bal);

        // Check 50% cap: read supply snapshot and period burned via vm.load
        uint256 snapshot = uint256(vm.load(address(sdgnrs), bytes32(SLOT_SUPPLY_SNAPSHOT)));
        uint256 currentBurned = uint256(vm.load(address(sdgnrs), bytes32(SLOT_PERIOD_BURNED)));

        if (snapshot != 0 && currentBurned + amount > snapshot / 2) {
            // Clamp to remaining capacity
            if (snapshot / 2 > currentBurned) {
                amount = snapshot / 2 - currentBurned;
            } else {
                return;
            }
        }

        if (amount == 0) return;

        vm.prank(currentActor);
        try sdgnrs.burn(amount) {
            ghost_totalBurned += amount;
        } catch {}
    }

    // =========================================================================
    //                     ACTION: ADVANCE DAY
    // =========================================================================

    /// @notice Advance the game by one day: warp + advanceGame + VRF fulfillment + advanceGame
    /// @param randomWord Random word for VRF fulfillment (fuzz input)
    function action_advanceDay(uint256 randomWord) external {
        calls_advanceDay++;

        // Warp past day boundary
        vm.warp(block.timestamp + 1 days);

        // First advanceGame -- may trigger VRF request
        try game.advanceGame() {} catch {}

        // Fulfill VRF if pending
        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
            }
        }

        // Second advanceGame -- processes VRF result, runs rngGate which resolves period
        try game.advanceGame() {} catch {}

        // Check for newly resolved periods
        _checkResolvedPeriods();
    }

    // =========================================================================
    //                        ACTION: CLAIM
    // =========================================================================

    /// @notice Claim a resolved gambling burn redemption for a random actor
    /// @param actorSeed Seed for actor selection
    function action_claim(uint256 actorSeed) external useActor(actorSeed) {
        calls_claim++;

        uint256 ethBefore = currentActor.balance;
        uint256 burnieBefore = coin.balanceOf(currentActor);

        vm.recordLogs();
        vm.prank(currentActor);
        try sdgnrs.claimRedemption() {
            ghost_claimCount++;
            ghost_totalEthClaimed += currentActor.balance - ethBefore;
            ghost_totalBurnieClaimed += coin.balanceOf(currentActor) - burnieBefore;

            // Parse RedemptionClaimed event for split tracking (INV-03)
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bytes32 claimedSig = keccak256("RedemptionClaimed(address,uint16,bool,uint256,uint256,uint256)");
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == claimedSig) {
                    (, , uint256 ethPayout, , uint256 lootboxEth) =
                        abi.decode(logs[i].data, (uint16, bool, uint256, uint256, uint256));
                    ghost_totalEthDirect += ethPayout;
                    ghost_totalLootboxEth += lootboxEth;
                    ghost_totalRolledEth += ethPayout + lootboxEth;
                    break;
                }
            }
        } catch {}

        // Attempt re-claim to test no-double-claim invariant.
        // CP-07 split claim: partial claim (ETH-only) leaves the claim alive for
        // BURNIE resolution. A second call that transfers zero ETH is expected.
        // Only flag a double claim if the re-claim actually pays ETH again.
        uint256 ethBeforeReClaim = currentActor.balance;
        vm.prank(currentActor);
        try sdgnrs.claimRedemption() {
            if (currentActor.balance > ethBeforeReClaim) {
                ghost_doubleClaim++;
            }
        } catch {}
    }

    // =========================================================================
    //                   ACTION: TRIGGER GAME OVER
    // =========================================================================

    /// @notice Warp far into the future to trigger game-over via liveness timeout
    function action_triggerGameOver() external {
        calls_triggerGameOver++;

        if (game.gameOver()) return;

        // Warp past liveness timeout (safe overshoot)
        vm.warp(block.timestamp + 90 days);

        // First advanceGame -- should trigger game-over path
        try game.advanceGame() {} catch {}

        // Fulfill VRF if pending
        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp)))) {} catch {}
            }
        }

        // Second advanceGame after VRF
        try game.advanceGame() {} catch {}
    }

    // =========================================================================
    //                     INTERNAL: CHECK RESOLVED PERIODS
    // =========================================================================

    /// @dev Read redemptionPeriodIndex via vm.load and check for period resolution events.
    ///      Updates ghost variables for period monotonicity and roll bounds.
    function _checkResolvedPeriods() private {
        // Read redemptionPeriodIndex (uint48 at slot 14)
        uint256 raw = uint256(vm.load(address(sdgnrs), bytes32(SLOT_PERIOD_INDEX)));
        uint256 currentPeriodIndex = uint48(raw & type(uint48).max);

        // Check monotonicity
        if (currentPeriodIndex < ghost_lastPeriodIndex) {
            ghost_periodIndexDecreased++;
        }

        // If new period, check the PREVIOUS period's roll
        if (currentPeriodIndex > ghost_lastPeriodIndex) {
            // Compute mapping slot for redemptionPeriods[ghost_lastPeriodIndex]
            // redemptionPeriods is at storage slot 8
            bytes32 slot = keccak256(abi.encode(uint256(ghost_lastPeriodIndex), uint256(8)));
            uint256 periodRaw = uint256(vm.load(address(sdgnrs), slot));

            // Extract roll (uint16, first field in RedemptionPeriod struct)
            uint16 roll = uint16(periodRaw & 0xFFFF);

            if (roll != 0 && (roll < 25 || roll > 175)) {
                ghost_rollOutOfBounds++;
            }

            ghost_periodsResolved++;
        }

        ghost_lastPeriodIndex = currentPeriodIndex;
    }

    // =========================================================================
    //                          HELPERS
    // =========================================================================

    /// @notice Get the number of actors
    /// @return Number of actors in the handler
    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Get actor address by index
    /// @param i Actor index
    /// @return Actor address
    function getActor(uint256 i) external view returns (address) {
        return actors[i];
    }
}
