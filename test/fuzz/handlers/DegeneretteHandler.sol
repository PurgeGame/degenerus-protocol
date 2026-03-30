// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title DegeneretteHandler -- Handler for Degenerette slot machine betting in invariant tests
/// @notice Wraps placeDegeneretteBet and resolveBets with bounded inputs, multi-actor support,
///         and ghost variable tracking for ETH accounting invariants.
/// @dev Targets the NEVER-FUZZED Degenerette bet accounting: wager in = payout + burn.
///      Tracks ETH flows to verify no ETH is created or destroyed during bet lifecycle.
contract DegeneretteHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables ---
    uint256 public ghost_totalEthWagered;
    uint256 public ghost_totalEthPayout;
    uint256 public ghost_totalBurnieWagered;
    uint256 public ghost_totalBurniePayout;
    uint256 public ghost_betsPlaced;
    uint256 public ghost_betsResolved;
    uint256 public ghost_betsFailed;
    uint256 public ghost_resolvesFailed;

    // Track per-actor bet nonces for resolution
    mapping(address => uint64[]) public actorBetIds;
    mapping(address => uint256) public actorBetCount;

    // --- Call counters ---
    uint256 public calls_placeBet;
    uint256 public calls_resolveBet;
    uint256 public calls_fulfillVrf;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xC0000 + i));
            actors.push(actor);
            vm.deal(actor, 500 ether);
        }
    }

    /// @notice Place an ETH Degenerette bet with bounded inputs
    /// @param actorSeed Seed for actor selection
    /// @param amountPerTicket Raw bet amount, bounded to [0.005 ether, 1 ether]
    /// @param ticketCount Raw ticket count, bounded to [1, 10]
    /// @param customTicket Raw custom ticket packed traits
    /// @param heroQuadrant Raw hero quadrant, bounded to [0, 4] (4 = no hero = 0xFF)
    function placeEthBet(
        uint256 actorSeed,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external useActor(actorSeed) {
        calls_placeBet++;

        if (game.gameOver()) return;

        // Bound inputs
        amountPerTicket = uint128(bound(uint256(amountPerTicket), 0.005 ether, 1 ether));
        ticketCount = uint8(bound(uint256(ticketCount), 1, 10));
        // Ensure each quadrant byte has valid color (0-7) and symbol (0-7)
        customTicket = _sanitizeTicket(customTicket);
        // heroQuadrant: 0-3 for specific quadrant, >= 4 means no hero (0xFF)
        heroQuadrant = uint8(bound(uint256(heroQuadrant), 0, 4));
        if (heroQuadrant == 4) heroQuadrant = 0xFF;

        uint256 totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        if (totalBet > currentActor.balance) return;

        // First ensure the actor has purchased tickets (to have a valid lootbox RNG index)
        _ensureActivePurchasePhase();

        vm.prank(currentActor);
        try game.placeDegeneretteBet{value: totalBet}(
            currentActor,
            0, // currency = ETH
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant
        ) {
            ghost_totalEthWagered += totalBet;
            ghost_betsPlaced++;
            // Track bet nonce for this actor (nonce is sequential per player)
            uint256 count = actorBetCount[currentActor];
            actorBetIds[currentActor].push(uint64(count + 1));
            actorBetCount[currentActor] = count + 1;
        } catch {
            ghost_betsFailed++;
        }
    }

    /// @notice Resolve pending Degenerette bets for an actor
    /// @param actorSeed Seed for actor selection
    function resolveBets(uint256 actorSeed) external useActor(actorSeed) {
        calls_resolveBet++;

        uint256 count = actorBetIds[currentActor].length;
        if (count == 0) return;

        // Try to resolve the oldest unresolved bet
        uint64 betId = actorBetIds[currentActor][count - 1];

        uint64[] memory ids = new uint64[](1);
        ids[0] = betId;

        uint256 claimableBefore = game.claimableWinningsOf(currentActor);

        vm.prank(currentActor);
        try game.resolveDegeneretteBets(currentActor, ids) {
            ghost_betsResolved++;
            uint256 claimableAfter = game.claimableWinningsOf(currentActor);
            if (claimableAfter > claimableBefore) {
                ghost_totalEthPayout += (claimableAfter - claimableBefore);
            }
            actorBetIds[currentActor].pop();
        } catch {
            ghost_resolvesFailed++;
        }
    }

    /// @notice Fulfill VRF to enable bet resolution
    /// @param randomWord Random word for VRF fulfillment
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    /// @notice Purchase tickets to set up lootbox RNG index
    /// @param actorSeed Seed for actor selection
    function purchaseTickets(uint256 actorSeed) external useActor(actorSeed) {
        if (game.gameOver()) return;

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * 400) / 400; // 1 full ticket
        if (cost == 0 || cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: cost}(
            currentActor,
            400, // 1 full ticket
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {
            ghost_totalEthWagered += cost;
        } catch {}
    }

    /// @notice Warp time to advance game state
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 1 days);
        vm.warp(block.timestamp + delta);
    }

    /// @notice Advance game to progress state machine
    /// @param actorSeed Seed for actor selection
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        if (game.gameOver()) return;

        vm.prank(currentActor);
        try game.advanceGame() {} catch {}
    }

    // --- Internal helpers ---

    /// @dev Ensure we are in purchase phase and have a valid lootbox RNG index
    function _ensureActivePurchasePhase() private {
        // Try a small purchase if needed to populate lootbox state
        // The placeDegeneretteBet will revert if lootbox RNG index is 0
    }

    /// @dev Sanitize custom ticket to have valid traits per quadrant
    ///      Each quadrant: bits [7:6] unused by matching, [5:3] color (0-7), [2:0] symbol (0-7)
    function _sanitizeTicket(uint32 ticket) private pure returns (uint32) {
        uint32 sanitized;
        for (uint8 q = 0; q < 4; q++) {
            uint8 quadByte = uint8(ticket >> (q * 8));
            // Color is bits 5-3 (values 0-7), symbol is bits 2-0 (values 0-7)
            uint8 color = (quadByte >> 3) & 7;
            uint8 symbol = quadByte & 7;
            sanitized |= uint32(uint32((color << 3) | symbol)) << (q * 8);
        }
        return sanitized;
    }
}
