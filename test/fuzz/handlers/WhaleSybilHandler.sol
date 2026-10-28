// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title WhaleSybilHandler -- Concurrent whale + Sybil pressure handler for invariant tests
/// @notice Simultaneously exercises whale pass purchases AND mass Sybil ticket buying.
///         Previous fuzzing only tested these independently. This handler combines them
///         to find: state corruption from concurrent large/small transactions, pool
///         accounting errors under mixed purchase types, whale price mismatches at
///         varying levels.
/// @dev Uses two actor pools: whales (high ETH, few actors) and sybils (low ETH, many actors).
///      Whale passes use dynamic price lookup to match current level pricing.
contract WhaleSybilHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables ---
    // The handler can start after a funded Degenesis week, not only at genesis.
    uint256 public immutable ghost_initialBacking;
    uint256 public ghost_whaleDeposited;
    uint256 public ghost_sybilDeposited;
    uint256 public ghost_whaleSuccessful;
    uint256 public ghost_sybilSuccessful;
    uint256 public ghost_whaleFailed;
    uint256 public ghost_sybilFailed;
    uint256 public ghost_totalClaimed;
    uint256 public ghost_advances; // successful mineFlip calls
    uint256 public ghost_vrfFulfillments; // VRF words delivered
    uint256 public ghost_claims; // claimWinnings calls that paid out

    // Pool tracking
    uint256 public ghost_maxGameBalance; // Game-held ETH + stETH backing
    uint256 public ghost_minObligationRatio; // basis points: backing * 10000 / obligations

    // --- Call counters ---
    uint256 public calls_whaleBuy;
    uint256 public calls_sybilBuy;
    uint256 public calls_claimWinnings;
    uint256 public calls_advanceGame;

    // This activity runs inside the first fuzz call, never during fixture setup.
    // Keep a failed required prefix observable even with fail_on_revert=false.
    bool public walkStarted;
    bool public walkPrefixComplete;
    bool public walkFailed;
    bytes public walkFailure;
    uint256 public walkPrefixSybils;
    uint256 public walkPrefixWhales;
    uint256 public walkPrefixWork;
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");

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
        ghost_initialBacking = SolvencyObligations.backing(game_);
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

    /// @notice Required mixed pressure once, then one unrestricted adversarial action.
    /// @dev Time skips and expected refusals remain unrestricted after the first call's prefix.
    ///      The self-call rollback preserves original error bytes in the outer walk; a failed
    ///      prefix is never retried or silently discarded by the invariant fuzzer.
    function walk(uint256 actionSeed, uint256 actorSeed, uint256 quantitySeed, uint256 wordSeed) external {
        if (!walkStarted) {
            walkStarted = true;
            try this.beginWalk(actorSeed, quantitySeed, wordSeed) {
                walkPrefixComplete = true;
            } catch (bytes memory reason) {
                walkFailed = true;
                walkFailure = reason;
            }
        }
        if (!walkPrefixComplete) return;

        uint256 action = actionSeed % 6;
        if (action == 0) this.whalePassPurchase(actorSeed, quantitySeed);
        else if (action == 1) this.sybilPurchase(actorSeed);
        else if (action == 2) this.whaleClaimWinnings(actorSeed);
        else if (action == 3) this.mineFlip(actorSeed);
        else if (action == 4) this.fulfillVrf(wordSeed);
        else this.warpTime(quantitySeed);
    }

    /// @dev First-trace admission uses fresh seeded accounts and exactly priced purchases.
    ///      Real ETH, mint activity, obligations and committed miner work provide witnesses.
    function beginWalk(uint256 actorSeed, uint256 quantitySeed, uint256 wordSeed) external {
        require(msg.sender == address(this), "WhaleSybil: prefix is self-only");
        require(!game.gameOver() && !game.livenessTriggered(), "WhaleSybil: prefix requires a live game");
        uint256 start = actorSeed % sybils.length;
        for (uint256 i; i < 4; ++i) {
            address buyer = sybils[(start + i) % sybils.length];
            (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
            uint256 cost = priceWei / 4;
            uint256 balanceBefore = buyer.balance;
            uint256 mintBefore = game.mintPackedFor(buyer);
            vm.prank(buyer);
            game.purchaseOrderFor{value: cost}(0, 100, 0, bytes32(0), MintPaymentKind.DirectEth, false);
            require(buyer.balance + cost == balanceBefore, "WhaleSybil: required sybil did not spend ETH");
            require(game.mintPackedFor(buyer) != mintBefore, "WhaleSybil: required sybil did not record activity");
            ghost_sybilDeposited += cost;
            ++ghost_sybilSuccessful;
            ++walkPrefixSybils;
            _trackBalance();
        }

        address whale = whales[actorSeed % whales.length];
        uint256 quantity = 1 + quantitySeed % 2;
        uint256 passLevel = uint256(game.currentLvl()) + 1;
        if (passLevel % 100 == 0) quantity = 2;
        uint256 price = (passLevel <= 4 ? 2.4 ether : 4 ether) * quantity;
        uint256 whaleBalance = whale.balance;
        uint256 whaleMint = game.mintPackedFor(whale);
        vm.prank(whale);
        game.purchaseWhalePass{value: price}(0, quantity, bytes32(0));
        require(whale.balance + price == whaleBalance, "WhaleSybil: required whale did not spend ETH");
        require(game.mintPackedFor(whale) != whaleMint, "WhaleSybil: required whale did not record activity");
        ghost_whaleDeposited += price;
        ++ghost_whaleSuccessful;
        ++walkPrefixWhales;
        _trackBalance();

        if (game.nextMinerAction() == 0) vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        uint256 request = vrf.lastRequestId();
        if (request != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(request);
            if (!fulfilled) {
                // Only required progress maps reserved words. Later adversarial deliveries
                // retain the original raw word, including reserved values zero and one.
                vrf.fulfillRandomWords(request, wordSeed < 2 ? wordSeed + 2 : wordSeed);
                ++ghost_vrfFulfillments;
            }
        }
        vm.recordLogs();
        vm.prank(whale);
        game.mineRun(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 2
                && logs[i].topics[0] == MINER_WORK
                && address(uint160(uint256(logs[i].topics[1]))) == whale) {
                (, uint256 executionGas,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                if (executionGas != 0) ++walkPrefixWork;
            }
        }
        require(walkPrefixWork == 1, "WhaleSybil: prefix miner made no progress");
        ++ghost_advances;
    }

    /// @notice Whale pass purchase with dynamic pricing
    /// @param actorSeed Seed for whale selection
    /// @param qty Raw quantity, bounded to [1, 5]
    function whalePassPurchase(
        uint256 actorSeed,
        uint256 qty
    ) external useWhale(actorSeed) {
        calls_whaleBuy++;

        if (game.gameOver()) return;

        qty = bound(qty, 1, 5);

        // Whale pass prices vary by level: 2.4 ETH (levels 0-3), 4 ETH (x49/x99)
        // We try with 2.4 ETH first; if that reverts, try 4 ETH
        uint256 cost = 2.4 ether * qty;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseWhalePass{value: cost}(0, qty, bytes32(0)) {
            ghost_whaleDeposited += cost;
            ghost_whaleSuccessful++;
            _trackBalance();
        } catch {
            // Try higher price (4 ETH per pass)
            cost = 4 ether * qty;
            if (cost <= currentActor.balance) {
                vm.prank(currentActor);
                try game.purchaseWhalePass{value: cost}(0, qty, bytes32(0)) {
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
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 cost = (priceWei * 100) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseOrderFor{value: cost}(
            0,
            100,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth, false
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
        try game.claimClaimable(0) {
            uint256 balAfter = currentActor.balance;
            if (balAfter > balBefore) {
                uint256 beforeClaimed = ghost_totalClaimed;
                ghost_totalClaimed += balAfter - balBefore;
                ghost_claims++;
                uint256 deposits = ghost_whaleDeposited + ghost_sybilDeposited;
                if (beforeClaimed <= deposits && ghost_totalClaimed > deposits) {
                    // A concrete witness for the old false-positive bound: these
                    // payouts also draw on prizes funded before this handler began.
                    emit log_string("WhaleSybil opening-backed claim");
                    emit log_named_uint("initial backing", ghost_initialBacking);
                    emit log_named_uint("new deposits", deposits);
                    emit log_named_uint("total claimed", ghost_totalClaimed);
                    emit log_named_uint("remaining backing", SolvencyObligations.backing(game));
                    emit log_named_uint("remaining obligations", SolvencyObligations.obligations(game));
                }
            }
        } catch {}
    }

    /// @notice Advance game
    /// @param actorSeed Seed for actor selection (uses whales or sybils alternately)
    function mineFlip(uint256 actorSeed) external {
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
        try game.mineRun(0) {
            ghost_advances++;
        } catch {}
    }

    /// @notice Fulfill VRF
    function fulfillVrf(uint256 randomWord) external {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        try vrf.fulfillRandomWords(reqId, randomWord) {
            ghost_vrfFulfillments++;
        } catch {}
    }

    /// @notice Warp time
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 2 days);
        vm.warp(block.timestamp + delta);
    }

    // --- Internal helpers ---

    /// @dev Track Game-held ETH + stETH backing vs obligations for solvency ratio
    function _trackBalance() private {
        uint256 gameBacking = SolvencyObligations.backing(game);
        if (gameBacking > ghost_maxGameBalance) {
            ghost_maxGameBalance = gameBacking;
        }

        // Canonical obligation set (freeze-window pending buffer included; dead post-GO live
        // pools excluded) -- SolvencyObligations. _trackBalance only runs right after a successful
        // purchase (gameOver is false there), but using the shared helper keeps the ratio honest
        // through any freeze window the purchase may have just opened.
        uint256 obligations = SolvencyObligations.obligations(game);

        if (obligations > 0) {
            uint256 ratio = (gameBacking * 10_000) / obligations;
            if (ratio < ghost_minObligationRatio) {
                ghost_minObligationRatio = ratio;
            }
        }
    }
}
