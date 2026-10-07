// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Production facade plus a native `runDailyPhase` seam (one daily stage per call) and
///      read-only views of the BAF work record and pools.
contract BafRebuyHost is DegenerusGame {
    function brDaily(uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runDailyPhase(uint256)", allowance));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    /// @dev True when the next daily phase is the consolidation (the advance selector's order).
    function brConsolidationNext() external view returns (bool) {
        return !_jackpotBattlePending() && !phaseTransitionActive && jackpotWork.kind == 0
            && !jackpotPhaseFlag && lastPurchaseDay && !_purchaseTicketLegPending();
    }

    function brWord() external view returns (uint256) {
        return _recordedDailyWord(rngRequestDay);
    }

    function brWork() external view returns (uint128 budget, uint128 paid, uint32 n, uint24 lvl, uint16 cursor, uint8 kind) {
        JackpotWork storage w = jackpotWork;
        return (w.budget, w.paid, w.traits, w.lvl, w.winner, w.kind);
    }

    function brPools()
        external
        view
        returns (uint256 next, uint256 future, uint256 current, uint256 claimable, uint256 pendingFuture, bool frozen)
    {
        (uint128 n, uint128 f) = _getPrizePools();
        (, uint128 pf) = _getPendingPools();
        return (n, f, currentPrizePool, claimablePool, pf, prizePoolFrozen);
    }
}

/// @title BafRebuyReconciliationTest -- the BAF reservation and its residue reconcile the pools
///        in an organically driven game.
///
/// @notice The level-10 consolidation debits futurePool and credits claimablePool by the award
///         schedule's ETH term (the reservation), a function of the BAF pool alone. The award
///         stage (stage 19) then pays each winner `bafPairWinners` / `bafHeadWinner` name from
///         that reservation and, with its last group, returns the ETH term of every unfilled
///         slot (the residue) to the pending future pool (the stage runs inside the daily
///         request's pool freeze) and closes the bracket (`finalizeBaf`). This test drives the real game to the level-10 transition with
///         an injected top BAF bettor, runs the consolidation and the award stage as separate
///         `runDailyPhase` calls, and checks: the reservation equals the schedule term; the
///         stage moves no pool but the residue; credits plus residue equal the reservation; the
///         top bettor takes head slot 0 (half its 10% as claimable ETH); the game then completes
///         the level and the future pool keeps its value.
///
/// @dev Deploys the full protocol via DeployProtocol. The level-10 transition word is forced odd
///      (winning flip), so the BAF fires rather than skips.
contract BafRebuyReconciliationTest is DeployProtocol {
    /// @dev Storage slot of prizePoolsPacked in DegenerusGameStorage (confirmed via forge inspect).
    ///      Layout: [upper 128 bits: futurePrizePool] [lower 128 bits: nextPrizePool]
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;

    bytes32 private constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    bytes32 private constant ETH_SIG = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 private constant CREDIT_SIG = keccak256("PlayerCredited(uint32,uint256)");
    bytes32 private constant SKIPPED_SIG = keccak256("BafSkipped(uint24,uint24)");
    uint8 private constant STAGE_ENTERED_JACKPOT = 7;
    uint8 private constant STAGE_JACKPOT_BAF_AWARDS = 19;
    uint16 private constant BAF_TRAIT_SENTINEL = 420;
    uint256 private constant ROUNDS = 48;
    uint256 private constant LOOTBOX_CLAIM_THRESHOLD = 5 ether;
    uint256 private constant HALF_WHALE_PASS_PRICE = 2.25 ether;
    uint256 private constant WIDE_ALLOWANCE = 60_000_000;

    address private buyer;
    bool private stageChecked;

    function setUp() public {
        _deployProtocol();
        // This fixture measures the level clock in days; keep sDGNRS's automatic whale
        // purchase (a per-level pool contribution) out of it.
        _pinSdgnrsWhaleBuyShut();
        vm.warp(block.timestamp + 1 days);

        // Create and fund buyer
        buyer = makeAddr("baf_rebuy_buyer");
        vm.deal(buyer, 100_000 ether);

        // Seed the game contract with ETH to back the prize pool injections.
        vm.deal(address(game), 2_000 ether);
    }

    /// @notice The level-10 BAF reserves its schedule at consolidation and reconciles the
    ///         residue at the stage's completion, then the game completes the level.
    function testBafRebuyContributionPreserved() public {
        uint256 simTime = block.timestamp; // starts at 86400 (deploy time)

        for (uint256 day = 0; day < 600; day++) {
            uint24 currentLevel = game.level();
            if (game.gameOver()) break;
            // Stop once level > 10 (the level-10 jackpot phase has ended).
            if (currentLevel > 10) break;

            simTime += 1 days + 1;
            vm.warp(simTime);

            _seedNextPrizePool(49.9 ether);
            _buyTickets(buyer, 4000);

            // Inject the buyer as the bracket-10 top bettor during level 10's purchase phase.
            if (currentLevel == 9) _injectBafTop(buyer, 10);

            for (uint256 j = 0; j < 50; j++) {
                _fulfillVrfIfPending();
                // The last-purchase request pre-increments the level: the consolidation is next.
                if (!stageChecked && game.level() == 10 && !game.jackpotPhase()) {
                    _checkLevelTenBaf();
                    stageChecked = true;
                    continue;
                }
                (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
                if (!ok) break;
            }
        }

        uint24 finalLevel = game.level();
        emit log_named_uint("Final level reached", finalLevel);
        assertTrue(stageChecked, "the level-10 BAF consolidation and award stage were observed");
        assertGt(finalLevel, 10, "Game advanced past level 10 (BAF trigger level)");

        // After the BAF, the residue return and the drawdown to the next pool, the future pool
        // keeps the bulk of the seeded 100 ETH.
        uint256 postFuture = _readFuturePrizePool();
        emit log_named_uint("Post-BAF futurePrizePool (after drawdown)", postFuture);
        assertGt(postFuture, 10 ether, "futurePrizePool retains significant value (> 10 ETH) after BAF cycle");
    }

    /// @dev From the level-10 last-purchase lock: advance one engine step at a time until the
    ///      next step would enter the jackpot phase (that step is rolled back), run the daily
    ///      legs ahead of the consolidation, then the consolidation and the award stage as one
    ///      `runDailyPhase` call each.
    function _checkLevelTenBaf() internal {
        for (uint256 i; i < 256; ++i) {
            _fulfillVrfIfPending();
            uint256 snap = vm.snapshotState();
            (bool ok, ) = address(game).call{gas: 6_000_000}(abi.encodeWithSignature("mineFlip()"));
            if (game.jackpotPhase()) {
                vm.revertToState(snap);
                break;
            }
            vm.deleteStateSnapshot(snap);
            if (!ok) break;
        }
        assertTrue(game.rngLocked() && !game.jackpotPhase() && game.level() == 10, "parked before consolidation");
        vm.etch(address(game), type(BafRebuyHost).runtimeCode);
        BafRebuyHost host = BafRebuyHost(payable(address(game)));
        // The engine step that enters the jackpot phase can also carry the daily legs before
        // the consolidation (the purchase battle); run those first, one phase per call.
        for (uint256 k; k < 16 && !host.brConsolidationNext(); ++k) host.brDaily{gas: 90_000_000}(WIDE_ALLOWANCE);
        assertTrue(host.brConsolidationNext(), "the consolidation is the next daily phase");
        // Seed futurePrizePool to exactly 100 ether right before the BAF draws from it.
        _seedFuturePrizePool(100 ether);

        // Consolidation: reserve the schedule's ETH term.
        vm.recordLogs();
        host.brDaily{gas: 90_000_000}(WIDE_ALLOWANCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_lastStage(logs), STAGE_ENTERED_JACKPOT, "the consolidation entered the jackpot phase");
        assertEq(_count(logs, SKIPPED_SIG), 0, "the winning flip resolves the bracket");
        (uint128 pool, uint128 reserve, uint32 n, uint24 wl, uint16 cursor, uint8 kind) = host.brWork();
        assertEq(kind, 7, "the award stage is armed");
        assertEq(wl, 10, "for bracket 10");
        assertEq(n, 2 * ROUNDS + 3, "99 award positions");
        assertEq(cursor, 0, "nothing paid at consolidation");
        assertEq(reserve, _reserve(pool), "the reservation is the schedule's ETH term");
        emit log_named_uint("BAF pool", pool);
        emit log_named_uint("BAF reservation", reserve);

        uint256 word = host.brWord();
        assertEq(jackpots.bafHeadWinner(10, word, 0), game.walletIdOf(buyer), "the injected bettor tops the board");
        assertEq(jackpots.bafHeadWinner(10, word, 1), 0, "nobody deposited on the armed day");
        assertEq(jackpots.bafHeadWinner(10, word, 2), 0, "the board has no third or fourth place");

        // Award stage: one call pays every group.
        (uint256 next0, uint256 future0, uint256 current0, uint256 claimable0, uint256 pending0, bool frozen0) =
            host.brPools();
        vm.recordLogs();
        host.brDaily{gas: 90_000_000}(WIDE_ALLOWANCE);
        logs = vm.getRecordedLogs();
        assertEq(_count(logs, ADVANCE_SIG), 1, "one daily stage ran");
        assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "the award stage ran");
        (,,,,, kind) = host.brWork();
        assertEq(kind, 0, "the stage completed and cleared its record");

        uint256 credited = _sum(logs, CREDIT_SIG) + _sum(logs, ETH_SIG);
        uint256 residue = reserve - credited;
        (uint256 next1, uint256 future1, uint256 current1, uint256 claimable1, uint256 pending1, bool frozen1) =
            host.brPools();
        assertEq(next1, next0, "the stage moves no next pool");
        assertEq(current1, current0, "the stage moves no current pool");
        assertTrue(frozen0 && frozen1, "the stage runs inside the daily request's pool freeze");
        assertEq(claimable0 - claimable1, residue, "only the residue leaves claimablePool");
        assertEq(pending1 - pending0, residue, "the residue joins the pending future pool");
        assertEq(future1, future0, "the frozen live future pool is untouched");
        uint256 headTerm = pool / 40 + (pool / 20 - pool / 40 > LOOTBOX_CLAIM_THRESHOLD
            ? (pool / 20 - pool / 40) % HALF_WHALE_PASS_PRICE : 0);
        assertGe(residue, 2 * headTerm, "the two empty head slots stay in the residue");
        emit log_named_uint("BAF residue", residue);

        bool topPaid;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 4 && logs[i].topics[0] == ETH_SIG
                && logs[i].topics[1] == bytes32(uint256(game.walletIdOf(buyer)))
                && logs[i].topics[3] == bytes32(uint256(BAF_TRAIT_SENTINEL))
                && keccak256(logs[i].data) == keccak256(abi.encode((uint256(pool) / 10) / 2, uint256(0)))) {
                topPaid = true;
            }
        }
        assertTrue(topPaid, "the top bettor takes half of head slot 0 as claimable ETH");
        assertEq(jackpots.bafHeadWinner(10, word, 0), 0, "finalizeBaf cleared the board");
    }

    /// @dev The schedule's ETH term: 48 rounds of (best (P/2)/48, second ((P*30)/100)/48) with
    ///      the small leg ETH when round and rank parity agree, then P/10, P/20, P/20 half ETH.
    function _reserve(uint256 pool) internal pure returns (uint256 reserve) {
        uint256 threshold = pool / 20;
        for (uint256 i; i < 2 * ROUNDS + 3; ++i) {
            uint256 a = i < 2 * ROUNDS
                ? (i & 1 == 0 ? (pool / 2) / ROUNDS : ((pool * 30) / 100) / ROUNDS)
                : (i == 2 * ROUNDS ? pool / 10 : pool / 20);
            if (a >= threshold) {
                uint256 lootbox = a - a / 2;
                reserve += a / 2 + (lootbox > LOOTBOX_CLAIM_THRESHOLD ? lootbox % HALF_WHALE_PASS_PRICE : 0);
            } else if (((i >> 1) ^ i) & 1 == 0) {
                reserve += a;
            } else if (a > LOOTBOX_CLAIM_THRESHOLD) {
                reserve += a % HALF_WHALE_PASS_PRICE;
            }
        }
    }

    function _lastStage(Vm.Log[] memory logs) internal view returns (uint8 stage) {
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE_SIG) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    function _count(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 c) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) ++c;
        }
    }

    function _sum(Vm.Log[] memory logs, bytes32 sig) internal view returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == sig) {
                total += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    // ==================== Internal Helpers ====================

    /// @notice Read futurePrizePool (future half, bits 128-255 of slot 2).
    function _readFuturePrizePool() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        return (packed >> 128) & ((uint256(1) << 128) - 1);
    }

    /// @notice Seed the next prize pool (low 128 bits of slot 2) to accelerate level transitions.
    /// @dev Preserves the future half.
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentNext = currentPacked & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        uint256 newPacked = (currentPacked & ~((uint256(1) << 128) - 1)) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Seed futurePrizePool (future half, bits 128-255 of slot 2) to a known value.
    /// @dev Preserves the next half.
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 newPacked = (currentPacked & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Inject buyer into the BAF leaderboard at level.
    /// @dev Uses vm.prank(coinflip) to call recordBafFlip (onlyCoin gate, coinflip-only).
    ///      The buyer gets a large BAF stake so they hold the #1 position (head slot 0: 10%).
    function _injectBafTop(address who, uint24 lvl) internal {
        // Record a large BAF flip to put the buyer at the top of the leaderboard.
        // 1000 ether stake = score 1000, the #1 position (head slot 0, 10% of the BAF pool).
        uint32 id = _giveWalletId(who);
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(id, lvl, 1000 ether);
    }

    /// @notice Buy tickets for the buyer at the current price.
    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        if (game.gameOver()) return;

        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;

        if (who.balance < cost) {
            vm.deal(who, cost + 10 ether);
        }

        vm.prank(who);
        try game.purchase{value: cost}(
            who,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth, false
        ) {} catch {}
    }

    /// @notice Check for pending VRF request and fulfill it with a deterministic random word.
    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 randomWord = uint256(keccak256(abi.encode(
            block.timestamp,
            game.level(),
            reqId
        )));
        // The level-10 transition word decides the BAF flip: force the winning branch.
        if (game.level() == 10 && !game.jackpotPhase()) randomWord |= 1;

        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }
}
