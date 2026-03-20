// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title WhaleSybilHandler -- Concurrent whale + Sybil pressure handler for invariant tests
/// @notice Simultaneously exercises whale bundle purchases AND mass Sybil ticket buying.
///         Previous fuzzing only tested these independently. This handler combines them
///         to find: state corruption from concurrent large/small transactions, pool
///         accounting errors under mixed purchase types, whale price mismatches at
///         varying levels.
/// @dev Uses two actor pools: whales (high ETH, few actors) and sybils (low ETH, many actors).
///      Whale bundles use dynamic price lookup to match current level pricing.
contract WhaleSybilHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables ---
    uint256 public ghost_whaleDeposited;
    uint256 public ghost_sybilDeposited;
    uint256 public ghost_whaleSuccessful;
    uint256 public ghost_sybilSuccessful;
    uint256 public ghost_whaleFailed;
    uint256 public ghost_sybilFailed;
    uint256 public ghost_totalClaimed;

    // Pool tracking
    uint256 public ghost_maxGameBalance;
    uint256 public ghost_minObligationRatio; // basis points: balance * 10000 / obligations

    // --- Call counters ---
    uint256 public calls_whaleBuy;
    uint256 public calls_sybilBuy;
    uint256 public calls_claimWinnings;
    uint256 public calls_advanceGame;

    // --- Actor management ---
    address[] public whales;
    address[] public sybils;
    address internal currentActor;

    modifier useWhale(uint256 seed) {
        currentActor = whales[bound(seed, 0, whales.length - 1)];
        _;
    }

    modifier useSybil(uint256 seed) {
        currentActor = sybils[bound(seed, 0, sybils.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numWhales, uint256 numSybils) {
        game = game_;
        vrf = vrf_;
        ghost_minObligationRatio = type(uint256).max;

        // Whales: few actors with massive ETH
        for (uint256 i = 0; i < numWhales; i++) {
            address whale = address(uint160(0xBB000 + i));
            whales.push(whale);
            vm.deal(whale, 1_000 ether);
        }

        // Sybils: many actors with small ETH
        for (uint256 i = 0; i < numSybils; i++) {
            address sybil = address(uint160(0xCC000 + i));
            sybils.push(sybil);
            vm.deal(sybil, 5 ether);
        }
    }

    /// @notice Whale bundle purchase with dynamic pricing
    /// @param actorSeed Seed for whale selection
    /// @param qty Raw quantity, bounded to [1, 5]
    function whaleBundlePurchase(
        uint256 actorSeed,
        uint256 qty
    ) external useWhale(actorSeed) {
        calls_whaleBuy++;

        if (game.gameOver()) return;

        qty = bound(qty, 1, 5);

        // Whale bundle prices vary by level: 2.4 ETH (levels 0-3), 4 ETH (x49/x99)
        // We try with 2.4 ETH first; if that reverts, try 4 ETH
        uint256 cost = 2.4 ether * qty;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseWhaleBundle{value: cost}(currentActor, qty) {
            ghost_whaleDeposited += cost;
            ghost_whaleSuccessful++;
            _trackBalance();
        } catch {
            // Try higher price (4 ETH per bundle)
            cost = 4 ether * qty;
            if (cost <= currentActor.balance) {
                vm.prank(currentActor);
                try game.purchaseWhaleBundle{value: cost}(currentActor, qty) {
                    ghost_whaleDeposited += cost;
                    ghost_whaleSuccessful++;
                    _trackBalance();
                } catch {
                    ghost_whaleFailed++;
                }
            } else {
                ghost_whaleFailed++;
            }
        }
    }

    /// @notice Sybil minimum-cost ticket purchase
    /// @param actorSeed Seed for sybil selection
    function sybilPurchase(uint256 actorSeed) external useSybil(actorSeed) {
        calls_sybilBuy++;

        if (game.gameOver()) return;

        // Buy minimum: 1/4 ticket (qty=100)
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * 100) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: cost}(
            currentActor,
            100,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {
            ghost_sybilDeposited += cost;
            ghost_sybilSuccessful++;
            _trackBalance();
        } catch {
            ghost_sybilFailed++;
        }
    }

    /// @notice Claim winnings for a whale
    /// @param actorSeed Seed for whale selection
    function whaleClaimWinnings(uint256 actorSeed) external useWhale(actorSeed) {
        calls_claimWinnings++;

        uint256 balBefore = currentActor.balance;

        vm.prank(currentActor);
        try game.claimWinnings(currentActor) {
            uint256 balAfter = currentActor.balance;
            if (balAfter > balBefore) {
                ghost_totalClaimed += balAfter - balBefore;
            }
        } catch {}
    }

    /// @notice Advance game
    /// @param actorSeed Seed for actor selection (uses whales or sybils alternately)
    function advanceGame(uint256 actorSeed) external {
        calls_advanceGame++;

        if (game.gameOver()) return;

        // Alternate between whale and sybil callers
        address caller;
        if (actorSeed % 2 == 0 && whales.length > 0) {
            caller = whales[bound(actorSeed, 0, whales.length - 1)];
        } else if (sybils.length > 0) {
            caller = sybils[bound(actorSeed, 0, sybils.length - 1)];
        } else {
            return;
        }

        vm.prank(caller);
        try game.advanceGame() {} catch {}
    }

    /// @notice Fulfill VRF
    function fulfillVrf(uint256 randomWord) external {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    /// @notice Warp time
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 2 days);
        vm.warp(block.timestamp + delta);
    }

    // --- Internal helpers ---

    /// @dev Track game balance vs obligations for solvency ratio
    function _trackBalance() private {
        uint256 gameBalance = address(game).balance;
        if (gameBalance > ghost_maxGameBalance) {
            ghost_maxGameBalance = gameBalance;
        }

        uint256 obligations = game.currentPrizePoolView()
            + game.nextPrizePoolView()
            + game.claimablePoolView()
            + game.futurePrizePoolView();

        if (obligations > 0) {
            uint256 ratio = (gameBalance * 10_000) / obligations;
            if (ratio < ghost_minObligationRatio) {
                ghost_minObligationRatio = ratio;
            }
        }
    }
}
