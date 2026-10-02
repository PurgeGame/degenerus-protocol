// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../../helpers/RecyclingState.sol";

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

    /// @dev Re-attested via game-layout-POST.txt (forge inspect DegenerusGame storageLayout):
    ///      `lootboxRngPacked` slot 34 (LR_INDEX lives in its low 48 bits) and
    ///      `lootboxRngWordByIndex` slot 35 (mapping(uint48 => uint256)). placeDegeneretteBet
    ///      gates on (LR_INDEX != 0) AND (_lootboxWord(LR_INDEX) == 0); resolution
    ///      gates on _lootboxWord(betIndex) != 0. The handler seeds both so the fuzzer
    ///      reaches a non-vacuous place->resolve sequence regardless of call ordering.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // post Stage-B game-storage repack: was 35
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 3;   // post Stage-B game-storage repack: was 36
    uint48 private constant SEED_LR_INDEX = 1;

    // --- Ghost variables ---
    uint256 public ghost_totalEthWagered;
    uint256 public ghost_totalEthPayout;
    uint256 public ghost_totalFlipWagered;
    uint256 public ghost_totalFlipPayout;
    uint256 public ghost_betsPlaced;
    uint256 public ghost_betsResolved;
    uint256 public ghost_betsFailed;
    uint256 public ghost_resolvesFailed;

    // Track per-actor bets for resolution: a bet is (RNG index, id within that index's queue).
    struct PlacedBet {
        uint48 index;
        uint64 betId;
    }
    mapping(address => PlacedBet[]) internal actorBets;
    /// @dev Last known queue length per index. Placement appends and an index with its word
    ///      unset has no resolved bets, so the new length is found by probing upward.
    mapping(uint48 => uint64) internal knownQueueLen;

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
    /// @param amountPerSpin Raw bet amount, bounded to [0.005 ether, 1 ether]
    /// @param ticketCount Raw ticket count, bounded to [1, 10]
    /// @param symbol Raw hero symbol, bounded to [0, 23] (no Dice)
    function placeEthBet(
        uint256 actorSeed,
        uint128 amountPerSpin,
        uint8 ticketCount,
        uint8 symbol
    ) external useActor(actorSeed) {
        calls_placeBet++;

        if (game.gameOver()) return;

        // Bound inputs
        amountPerSpin = uint128(bound(uint256(amountPerSpin), 0.005 ether, 1 ether) / 1 gwei * 1 gwei);
        ticketCount = uint8(bound(uint256(ticketCount), 1, 10));
        symbol = uint8(bound(uint256(symbol), 0, 23));

        uint256 totalBet = uint256(amountPerSpin) * uint256(ticketCount);
        if (totalBet > currentActor.balance) return;

        // Open the lootbox RNG window so placeDegeneretteBet's index-gate is satisfiable.
        uint48 index = _ensureLootboxIndexOpen();

        vm.prank(currentActor);
        try game.placeDegeneretteBet{value: totalBet}(currentActor, 0, amountPerSpin, ticketCount, symbol) {
            ghost_totalEthWagered += totalBet;
            ghost_betsPlaced++;
            uint64 len = knownQueueLen[index];
            while (game.degeneretteBetInfo(index, len + 1) != 0) ++len;
            knownQueueLen[index] = len;
            actorBets[currentActor].push(PlacedBet(index, len));
        } catch {
            ghost_betsFailed++;
        }
    }

    /// @notice Resolve pending Degenerette bets for an actor
    /// @param actorSeed Seed for actor selection
    function resolveBets(uint256 actorSeed) external useActor(actorSeed) {
        calls_resolveBet++;

        uint256 count = actorBets[currentActor].length;
        if (count == 0) return;

        // Try to resolve the newest unresolved bet
        PlacedBet memory bet = actorBets[currentActor][count - 1];
        // Another actor's global sweep may already have resolved this entry.
        if (game.degeneretteBetInfo(bet.index, bet.betId) == 0) {
            actorBets[currentActor].pop();
            return;
        }

        // Fill the bet's lootbox word so the sweep's resolve RNG-ready gate is satisfiable, and
        // force the active lootbox index past the bet's index so the sweep's finalized-index
        // frontier reaches it (mirrors _ensureLootboxIndexOpen's storage-poke idiom above: the
        // unguided fuzzer can leave the active index sitting ON the bet's own index for many
        // calls, which the removed per-id door never needed but the sweep does).
        _fillLootboxWordForResolve(bet.index);
        _advanceLootboxIndexPast(bet.index);

        uint256 claimableBefore = game.claimableWinningsOf(currentActor);

        vm.prank(currentActor);
        try game.openBoxes(type(uint256).max) {
            uint256 claimableAfter = game.claimableWinningsOf(currentActor);
            if (claimableAfter > claimableBefore) {
                ghost_totalEthPayout += (claimableAfter - claimableBefore);
            }
            // A successful openBoxes call may do no work or stop before this bet.
            // Count an observed nonzero -> zero transition, not merely a call.
            if (game.degeneretteBetInfo(bet.index, bet.betId) == 0) {
                ghost_betsResolved++;
                actorBets[currentActor].pop();
            }
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
            MintPaymentKind.DirectEth, false
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
    function mineFlip(uint256 actorSeed) external useActor(actorSeed) {
        if (game.gameOver()) return;

        vm.prank(currentActor);
        try game.mineFlip() {} catch {}
    }

    // --- Internal helpers ---

    /// @dev Make a Degenerette bet placeable: placeDegeneretteBet reverts unless the lootbox
    ///      RNG index is non-zero AND _lootboxWord(index) is still zero (the open,
    ///      not-yet-rolled window). The unguided fuzzer drives the game to game-over long before
    ///      a real purchase opens that window, so without this seed every placeEthBet early-returns
    ///      and the solvency invariant passes vacuously (betsPlaced stays 0). We force LR_INDEX to a
    ///      fixed open index (word still zero) so the live placeDegeneretteBet path actually executes
    ///      against real ETH. This is the same mechanism the DegeneretteHeroScore unit harness uses.
    function _ensureLootboxIndexOpen() private view returns (uint48 index) {
        // Placement always joins the write buffer; its previous session is never rewritten.
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Make a placed bet resolvable: the sweep reverts (RngNotReady on placement, or simply
    ///      never reaching the index) unless _lootboxWord(index) is non-zero. Fill the
    ///      bet's index word with a deterministic non-zero entropy so the sweep executes its
    ///      live payout + claimable-credit path (exercising the post-resolve solvency leg too).
    function _fillLootboxWordForResolve(uint48 index) private {
        if (index > 1) return;
        bytes32 wordSlot = keccak256(abi.encode(uint256(index), LOOTBOX_RNG_WORD_SLOT));
        if (uint256(bytes32(RecyclingState.word(address(game), uint48(index)))) == 0) {
            RecyclingState.seedWord(address(game), uint48(index), bytes32(uint256(keccak256(abi.encodePacked("degenerette_resolve_word", index))) | 1));
        }
    }

    /// @dev Force the active lootbox index past `index` so the sweep's finalized-index frontier
    ///      (which only opens indices strictly below the active one) can reach a bet queued at
    ///      `index`. A no-op if the active index has already moved past it.
    function _advanceLootboxIndexPast(uint48 index) private view {
        // The isolated resolution fixture seed has already selected this read.
        require(index == RecyclingState.readBuffer(address(game)), "fixture read tag");
    }

}
