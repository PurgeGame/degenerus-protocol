// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title SdgnrsLevelHighPasses -- the house's level cut, banked as high-roller craps passes.
/// @notice At every level close (`_consolidatePoolsAndRewardJackpots`) sDGNRS is handed a
///         twentieth of the consolidated pool, priced in FLIP at that level, as HIGH-ROLLER day
///         passes through `creditPasses` — one pass per HIGH_ROLLER_DAY_PASS_VALUE, whole passes
///         only, and no coinflip stake. The table then spends them on its own: the daily seat
///         reaches for a banked high pass before FLIP and sits the house at the day's high
///         multiple. Driven through the REAL game, the REAL advance and the REAL table.
///         Test-only: ZERO contracts/*.sol mutation.
contract SdgnrsLevelHighPasses is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    uint256 private constant POOL_HALF_MASK = (uint256(1) << 128) - 1;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint256 private constant HIGH_ROLLER_DAY_PASS_VALUE = 19 * 22_800 ether;

    bytes32 private constant POOLS_SETTLED_SIG =
        keccak256("PoolsSettled(uint24,uint24,uint24,uint256,uint256,uint256,uint256,uint256,uint256)");
    bytes32 private constant PASSES_CREDITED_SIG = keccak256("CrapsPassesCredited(address,bool,uint256)");

    address private buyer1;
    address private buyer2;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer1 = makeAddr("house_passes_buyer1");
        buyer2 = makeAddr("house_passes_buyer2");
        vm.deal(buyer1, 50_000 ether);
        vm.deal(buyer2, 50_000 ether);
        vm.deal(address(game), 100_000 ether);
    }

    /// @notice Each level close credits sDGNRS exactly `currentPool * 1000 / (price * 20 *
    ///         HIGH_ROLLER_DAY_PASS_VALUE)` high passes, rounded down, read off the same
    ///         `PoolsSettled` the consolidation emits — summed over every level the run closes,
    ///         against the `CrapsPassesCredited` the table logged at each close. Nothing lands in
    ///         the normal lane: the fraction under a whole high pass is dropped.
    function test_LevelCloseBanksHighPassesToSdgnrs() public {
        (uint256 normalBefore, uint256 highBefore) = crapsBattle.passCreditsOf(ContractAddresses.SDGNRS);
        assertEq(highBefore, 0, "fixture: no high passes banked at deploy");

        vm.recordLogs();
        _driveToLevel(3);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 settles;
        uint256 expectedHigh;
        uint256 creditedHigh;
        uint256 creditedNormal;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(game) || l.topics[0] != POOLS_SETTLED_SIG) continue;
            uint24 lvl = uint24(uint256(l.topics[1]));
            (, , , , uint256 currentPool, , , ) =
                abi.decode(l.data, (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256));
            expectedHigh += (currentPool * PRICE_COIN_UNIT)
                / (PriceLookupLib.priceForLevel(lvl) * 20 * HIGH_ROLLER_DAY_PASS_VALUE);
            ++settles;
            // The credit lands in the same tx, right before `PoolsSettled` — one log, the high
            // lane. Reading only there keeps a pass sDGNRS won off a lootbox elsewhere in the run
            // out of the count.
            for (uint256 back = 1; back <= 1 && back <= i; ++back) {
                Vm.Log memory c = logs[i - back];
                if (
                    c.emitter != address(crapsBattle) || c.topics[0] != PASSES_CREDITED_SIG
                        || address(uint160(uint256(c.topics[1]))) != ContractAddresses.SDGNRS
                ) break;
                (bool high, uint256 count) = abi.decode(c.data, (bool, uint256));
                if (high) creditedHigh += count;
                else creditedNormal += count;
            }
        }
        assertGe(settles, 1, "fixture: at least one level closed");
        assertGt(expectedHigh, 0, "fixture: the pool was large enough for a whole high pass");
        assertEq(creditedHigh, expectedHigh, "high passes credited == the level cut in whole high passes");
        assertEq(creditedNormal, 0, "the level cut never lands in the normal lane");

        // What the run banked minus what the daily seat already spent: the seat takes one high
        // pass per opened day, and the bank can only move through those two doors.
        (uint256 normalAfter, uint256 highAfter) = crapsBattle.passCreditsOf(ContractAddresses.SDGNRS);
        assertLe(highAfter, creditedHigh, "the bank holds no more than was credited");
        assertLe(normalAfter, normalBefore, "the seed normals only ever go down");
    }

    /// @notice A banked high pass is spent by the house's own daily seat, at the day's high
    ///         multiple, with no door of sDGNRS's own: bank one high pass, open a day, and the
    ///         house sits HIGH with the pass gone.
    function test_HouseSeatsHighOffTheBankedPass() public {
        crapsBattle.setPassCredits(ContractAddresses.SDGNRS, 0, 1);
        _driveUntilDayOpens();
        uint24 today = crapsBattle.currentDayIndex();
        assertTrue(_dayOpen(today), "fixture: a craps day opened");
        assertTrue(crapsBattle.daySeatIsHigh(today, ContractAddresses.SDGNRS), "the house sits HIGH");
        (, uint256 high) = crapsBattle.passCreditsOf(ContractAddresses.SDGNRS);
        assertEq(high, 0, "the seat spent the banked high pass");
        assertGe(crapsBattle.dayHighTicketsOf(today, 0), 1, "the day's high field counts the house");
    }

    // ---------------------------------------------------------------------------------------
    // Harness (ported from TicketLifecycle; test-only)
    // ---------------------------------------------------------------------------------------

    function _dayOpen(uint24 day) internal view returns (bool) {
        (uint24 openedDay,) = crapsBattle.bonusDayOf();
        return openedDay == day && day != 0;
    }

    function _driveUntilDayOpens() internal {
        uint256 simTime = block.timestamp;
        for (uint256 day = 0; day < 12; ++day) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _buyTickets(buyer1, 400);
            for (uint256 j = 0; j < 40; ++j) {
                _fulfillVrfIfPending();
                (bool ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                if (!ok) {
                    _fulfillVrfIfPending();
                    (ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                    if (!ok) break;
                }
            }
            if (_dayOpen(crapsBattle.currentDayIndex())) return;
        }
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentNext = currentPacked & POOL_HALF_MASK;
        if (currentNext >= targetNext) return;
        uint256 newPacked = (currentPacked & ~POOL_HALF_MASK) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 50 ether);
        vm.prank(who);
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord =
            uint256(keccak256(abi.encode(block.timestamp, game.level(), reqId, blockhash(block.number - 1))));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    function _driveToLevel(uint256 targetLevel) internal {
        uint256 simTime = block.timestamp;
        for (uint256 w = 0; w < 30; w++) {
            _fulfillVrfIfPending();
            (bool ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) break;
        }
        for (uint256 day = 0; day < 500; day++) {
            if (game.level() >= targetLevel || game.gameOver()) break;
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(500 ether);
            _buyTickets(buyer1, 4000);
            _buyTickets(buyer2, 2000);
            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfIfPending();
                (bool ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                if (!ok) {
                    _fulfillVrfIfPending();
                    (ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                    if (!ok) break;
                }
            }
        }
    }
}
