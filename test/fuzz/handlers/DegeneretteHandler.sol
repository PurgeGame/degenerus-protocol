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

    /// @dev Re-attested via game-layout-POST.txt (forge inspect DegenerusGame storageLayout):
    ///      `lootboxRngPacked` slot 34 (LR_INDEX lives in its low 48 bits) and
    ///      `lootboxRngWordByIndex` slot 35 (mapping(uint48 => uint256)). placeDegeneretteBet
    ///      gates on (LR_INDEX != 0) AND (lootboxRngWordByIndex[LR_INDEX] == 0); resolution
    ///      gates on lootboxRngWordByIndex[betIndex] != 0. The handler seeds both so the fuzzer
    ///      reaches a non-vacuous place->resolve sequence regardless of call ordering.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33; // post Stage-B game-storage repack: was 35
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 34;   // post Stage-B game-storage repack: was 36
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
    /// @param symbol Raw hero symbol, bounded to [0, 31]
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
        symbol = uint8(bound(uint256(symbol), 0, 31));

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

        uint64[] memory ids = new uint64[](1);
        ids[0] = bet.betId;

        // Fill the bet's lootbox word so the resolve RNG-ready gate is satisfiable.
        _fillLootboxWordForResolve(bet.index);

        uint256 claimableBefore = game.claimableWinningsOf(currentActor);

        vm.prank(currentActor);
        try game.resolveDegeneretteBets(bet.index, ids) {
            ghost_betsResolved++;
            uint256 claimableAfter = game.claimableWinningsOf(currentActor);
            if (claimableAfter > claimableBefore) {
                ghost_totalEthPayout += (claimableAfter - claimableBefore);
            }
            actorBets[currentActor].pop();
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
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        if (game.gameOver()) return;

        vm.prank(currentActor);
        try game.advanceGame() {} catch {}
    }

    // --- Internal helpers ---

    /// @dev Make a Degenerette bet placeable: placeDegeneretteBet reverts unless the lootbox
    ///      RNG index is non-zero AND lootboxRngWordByIndex[index] is still zero (the open,
    ///      not-yet-rolled window). The unguided fuzzer drives the game to game-over long before
    ///      a real purchase opens that window, so without this seed every placeEthBet early-returns
    ///      and the solvency invariant passes vacuously (betsPlaced stays 0). We force LR_INDEX to a
    ///      fixed open index (word still zero) so the live placeDegeneretteBet path actually executes
    ///      against real ETH. This is the same mechanism the DegeneretteHeroScore unit harness uses.
    function _ensureLootboxIndexOpen() private returns (uint48 index) {
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))
        );
        index = uint48(lrPacked);
        if (index == 0) {
            lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(SEED_LR_INDEX);
            vm.store(
                address(game),
                bytes32(LOOTBOX_RNG_PACKED_SLOT),
                bytes32(lrPacked)
            );
            index = SEED_LR_INDEX;
        }
        // Keep the word at the active index zero so the place-gate (word == 0) holds.
        bytes32 wordSlot = keccak256(abi.encode(uint256(index), LOOTBOX_RNG_WORD_SLOT));
        if (uint256(vm.load(address(game), wordSlot)) != 0) {
            vm.store(address(game), wordSlot, bytes32(uint256(0)));
        }
    }

    /// @dev Make a placed bet resolvable: resolveDegeneretteBets reverts (RngNotReady) unless
    ///      lootboxRngWordByIndex[index] is non-zero. Fill the bet's index word with a
    ///      deterministic non-zero entropy so resolveDegeneretteBets executes its live payout +
    ///      claimable-credit path (exercising the post-resolve solvency leg too).
    function _fillLootboxWordForResolve(uint48 index) private {
        if (index == 0) return;
        bytes32 wordSlot = keccak256(abi.encode(uint256(index), LOOTBOX_RNG_WORD_SLOT));
        if (uint256(vm.load(address(game), wordSlot)) == 0) {
            vm.store(
                address(game),
                wordSlot,
                bytes32(uint256(keccak256(abi.encodePacked("degenerette_resolve_word", index))) | 1)
            );
        }
    }

}
