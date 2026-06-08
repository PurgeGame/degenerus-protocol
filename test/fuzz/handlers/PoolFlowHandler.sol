// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title PoolFlowHandler — invariant handler driving the four-pool value flow for FUZZ-05 (POOL-CONSERVATION)
/// @notice Exercises the operations that MOVE value between the four prize pools so the conservation oracle in
///         PoolConservation.inv.t.sol has real transfers to observe (a vacuous green — pools that never move —
///         would prove nothing). Three actions:
///           (1) buy      — a real ETH purchase; msg.value enters the campaign and is split toward the
///                          next/future pools (and partly out to affiliate/jackpot/vault). Tracks the cumulative
///                          msg.value actually sent as ghost_realInflow.
///           (2) advance  — satisfies the daily purchase gate then drives advanceGame x3 + fulfills any pending
///                          VRF. advanceGame is what triggers _consolidatePoolsAndRewardJackpots: the future->next,
///                          next->current consolidation, the time-based future-take skim, and the jackpot
///                          settlement that credits claimable. Each successful advanceGame bumps ghost_advances —
///                          this is the non-vacuity witness that pool-to-pool transfers actually ran.
///           (3) claim    — claimWinnings, a real ETH OUTFLOW (the claimable pool is debited and ETH leaves the
///                          game to the actor). Tracks the realized payout delta as ghost_realOutflow.
///
/// @dev The conservation property this handler feeds is: the summed four-pool obligation is always backed by
///      ETH+stETH and never exceeds the real ETH that actually entered (startingBacking + ghost_realInflow) — an
///      internal transfer (future->next->current, skim, jackpot credit) can only RESHAPE the split across pools,
///      never inflate the total out of thin air. For that test to be honest the handler must move every wei
///      through real contract entrypoints: it NEVER vm.stores a pool value into existence (which would test the
///      seeder, not the contract). The only vm cheats used are vm.deal (fund the actors' wallets) and vm.prank
///      (act as an actor) — neither writes a pool. All pool mutation is the contract's own doing.
contract PoolFlowHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost ledger: the REAL ETH that crossed the contract boundary -------------------------------------
    // ghost_realInflow  : Σ msg.value across successful buys (the only way fresh ETH enters the pools).
    // ghost_realOutflow : Σ ETH paid out across successful claims (the only way pool-backing ETH leaves).
    // The conservation oracle asserts sum(4 pools) <= startingBacking + ghost_realInflow: the obligation the
    // contract recognizes can never exceed the real ETH that funded it, so an unbacked-credit mint is caught.
    uint256 public ghost_realInflow;
    uint256 public ghost_realOutflow;

    // --- Non-vacuity witness: pool-to-pool transfers actually occurred -------------------------------------
    // Each successful advanceGame runs the consolidation/skim/jackpot transfer machinery. If this stays 0 the
    // conservation property is vacuously true (nothing ever moved) and the plan FAILS acceptance.
    uint256 public ghost_advances;

    // --- Call counters (coverage visibility) --------------------------------------------------------------
    uint256 public calls_buy;
    uint256 public calls_advance;
    uint256 public calls_claim;
    uint256 public success_buy;
    uint256 public success_claim;

    // --- Actors (the sole ticket buyers ⇒ the sole external ETH source/sink) -------------------------------
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        // Disjoint actor base (0x90010 +) so this handler's actors never alias another handler's tracked set.
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0x90010 + i));
            actors.push(actor);
            vm.deal(actor, 1_000 ether);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =========================================================================
    // Action 1: buy — real ETH inflow toward the next/future pools
    // =========================================================================

    /// @notice Purchase tickets (optionally with a small lootbox amount) paying fresh ETH. The msg.value sent
    ///         enters the campaign and the mint module routes it: a share grows the next/future prize pools, the
    ///         rest flows out to affiliate / jackpots / vault. On success the full sent value is added to
    ///         ghost_realInflow — the conservation bound treats every entering wei as backing for the pools, so
    ///         the pool obligation can only be a SUBSET of inflow, never exceed it.
    function buy(uint256 actorSeed, uint256 qtySeed, uint256 boxSeed) external useActor(actorSeed) {
        calls_buy++;
        if (game.gameOver()) return;

        uint256 qty = bound(qtySeed, 400, 4000); // whole-ticket multiples (1 ticket = 4 entries = 1 price)
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost == 0) return;

        // A small optional lootbox top-up so the future/next split is exercised under varied inflow shapes.
        uint256 boxAmt = bound(boxSeed, 0, 0.5 ether);
        uint256 sent = ticketCost + boxAmt;
        if (sent > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: sent}(currentActor, qty, boxAmt, bytes32(0), MintPaymentKind.DirectEth) {
            success_buy++;
            ghost_realInflow += sent; // real ETH that crossed into the contract
        } catch {}
    }

    // =========================================================================
    // Action 2: advance — drives the pool-to-pool consolidation / skim / jackpot transfers
    // =========================================================================

    /// @notice Satisfy the daily purchase gate with one whole ticket, then advance the state machine x3 and
    ///         fulfill any pending VRF. advanceGame is the production entry to _consolidatePoolsAndRewardJackpots,
    ///         which performs the future->next, next->current consolidation, the time-based future-take skim, and
    ///         the jackpot settlement that credits the claimable pool — i.e. the very pool-to-pool transfers the
    ///         conservation oracle watches. Each successful advanceGame bumps ghost_advances (the non-vacuity
    ///         witness). The gate buy's msg.value is also real inflow and is tracked.
    function advance(uint256 actorSeed, uint256 wordSeed) external useActor(actorSeed) {
        calls_advance++;
        if (game.gameOver()) return;

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 gate = (priceWei * 400) / 400; // one whole ticket to satisfy the daily purchase gate
        if (gate != 0 && gate <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: gate}(currentActor, 400, 0, bytes32(0), MintPaymentKind.DirectEth) {
                ghost_realInflow += gate;
            } catch {}
        }

        for (uint256 i; i < 3; i++) {
            vm.prank(currentActor);
            try game.advanceGame() {
                ghost_advances++; // a consolidation/skim/jackpot transfer pass ran — non-vacuity witness
            } catch {}
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    // Odd word (| 1) so a zero-word guard never rejects the fulfillment.
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(wordSeed, i))) | 1) {} catch {}
                }
            }
        }
    }

    // =========================================================================
    // Action 3: claim — real ETH outflow (the claimable pool is debited)
    // =========================================================================

    /// @notice Claim `currentActor`'s winnings via the public claimWinnings. This debits the claimable pool and
    ///         pays ETH out of the game to the actor — a real outflow. The realized balance delta is added to
    ///         ghost_realOutflow so the ledger reflects ETH that left the backing. (The conservation bound stays
    ///         directionally safe even without subtracting outflow: outflow only shrinks the obligation, so
    ///         sum(4 pools) <= startingBacking + inflow continues to hold; ghost_realOutflow is tracked for the
    ///         diagnostic / completeness of the in-vs-out ledger.)
    function claim(uint256 actorSeed) external useActor(actorSeed) {
        calls_claim++;
        uint256 balBefore = currentActor.balance;
        vm.prank(currentActor);
        try game.claimWinnings(currentActor) {
            success_claim++;
            if (currentActor.balance > balBefore) {
                ghost_realOutflow += currentActor.balance - balBefore;
            }
        } catch {}
    }
}
