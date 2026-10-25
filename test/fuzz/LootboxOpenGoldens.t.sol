// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title LootboxOpenGoldens -- one fixed word, every reward figure a box open reports
/// @notice The box rewards are pure functions of the committed word: target level, ticket
///         variance tier, large-box FLIP variance, DGNRS pool tier, and craps-pass rounding. Their formulas live in private functions no harness can call,
///         and mutation v78 rewrote dozens of their operators without any foundry assertion
///         noticing. Under a fixed word every figure is fixed, so this opens one order on one word
///         and pins the exact figures it reports.
contract LootboxOpenGoldens is DeployProtocol {
    address internal actor;

    bytes32 internal constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant QUEUED = keccak256("EntriesQueued(uint32,uint24,uint32)");
    bytes32 internal constant DGNRS = keccak256("LootBoxDgnrsBatch(uint32,uint256,uint256)");
    bytes32 internal constant PASSES = keccak256("LootBoxCrapsPasses(uint32,uint32,uint32,uint24)");
    bytes32 internal constant REWARD = keccak256("LootBoxReward(uint32,uint8,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _word(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev The mid-day request, issued by `caller`'s mineFlip as the engine's next action (the
    ///      only door to a mid-day word). Returns the fresh request's ID.
    function _mineMiddayRequest(address caller) internal returns (uint256 reqId) {
        uint256 prior = mockVRF.lastRequestId();
        vm.prank(caller);
        game.mineFlip(0);
        reqId = mockVRF.lastRequestId();
        assertGt(reqId, prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
    }

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.mineFlip(0) {} catch {}
            if (game.rngLocked()) break;
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("daily", i))) | 1) {} catch {}
                }
            }
        }
        for (uint256 i; i < 10 && game.rngLocked(); i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("dailyword", i))) | 1) {} catch {}
                }
            }
            vm.prank(actor);
            try game.mineFlip(0) {} catch {}
        }
        // A fresh request waits for every read consumer of the day's cohort to finish. A shut
        // craps window the day bound to the write buffer rides the next request, which the engine
        // makes as mid-day work; answer and drain it too, until the engine is idle.
        for (uint256 i; i < 20; i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("trailing", i))) | 1);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) break;
            if (!game.advanceDue()) continue; // a fresh request waits for its word
            vm.prank(actor);
            game.mineFlip(0);
        }
        assertTrue(game.rngComplete(), "harness: the day's cohorts all completed");
    }

    /// @dev Fulfil the pending mid-day request and run the engine once: it publishes the word and
    ///      resolves the whole read cohort, the human orders included, as read consumers.
    function _fulfilAndOpen(uint256 vrfWord) internal returns (Vm.Log[] memory logs) {
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), vrfWord);
        vm.recordLogs();
        vm.prank(actor);
        game.mineFlip(0);
        logs = vm.getRecordedLogs();
    }

    struct Opened { uint256 amount; uint24 level; uint32 tickets; uint256 flip; bool up; }

    /// @dev Event tag of the fixture's entry: QUEUED_ENTRY_TAG | position << 1 | buffer.
    uint48 internal constant QUEUED_ENTRY_TAG = uint48(1) << 46;
    uint48 internal constant WHALE_REF = QUEUED_ENTRY_TAG; // buffer 0, position 0

    /// @dev The golden fixture: on buffer 0, the whale's order of twelve 0.15 ETH boxes is entry 0.
    ///      Every
    ///      queued seed is H(19, H(20, word, position), n), so the
    ///      pinned figures use the final domains and position; the fixture also asserts the owner. The
    ///      purchase freezes score 1: a 90.16% multiplier, below neutral, so no EV
    ///      allowance is drawn and every box scales by exactly 9016 bps.
    function _goldenFixture() internal returns (address whale) {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        assertEq(game.level(), 0, "golden fixture level");
        assertEq(priceWei, 0.01 ether, "golden fixture price");
        assertEq(_idx(), 0, "golden fixture tag");
        assertEq(RecyclingState.boxCount(address(game), 0), 0, "golden fixture: empty buffer");
        whale = makeAddr("goldenBuyer");
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        game.purchase{value: 12 * 0.15 ether + priceWei + 1 ether}(0, 400, BoxOrderLib.boCustoms(12, 0.15 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(RecyclingState.boxCount(address(game), 0), 1, "golden fixture: one entry");
        assertEq(BoxOrderLib.boId(RecyclingState.boxEntry(address(game), 0, 0)), 5, "golden fixture: whale wallet ID 5 at position 0");
        assertEq(BoxOrderLib.boScore(RecyclingState.boxEntry(address(game), 0, 0)), 1, "golden fixture: whale's frozen score");
    }

    /// @dev Fixed word ("golden_word", 28): nine plain boxes of twelve (the same target levels the
    ///      first nine nonces always rolled), five queued levels, one DGNRS batch.
    ///      Values are pinned below.
    function test_goldensUnderOneWord() public {
        address whale = _goldenFixture();
        _mineMiddayRequest(actor);
        Vm.Log[] memory logs = _fulfilAndOpen(uint256(keccak256(abi.encode("golden_word", uint256(28)))) | 1);
        assertGt(_word(0), 0, "the word landed");
        assertTrue(game.boxIndexComplete(0), "opened");

        Opened[9] memory opened;
        uint256 nOpened;
        uint256[8] memory qLevel;
        uint256[8] memory qEntries;
        uint256 nQueued;
        uint256[8] memory dReq;
        uint256[8] memory dPaid;
        uint256 nDgnrs;
        uint256 nPasses;
        uint32 whaleId = game.walletIdOf_g3120(whale);
        for (uint256 i; i < logs.length; i++) {
            // The engine call also carries unindexed engine events (Advance, MinerWork, ...).
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 t = logs[i].topics[0];
            uint32 who = uint32(uint256(logs[i].topics[1]));
            if (t == OPENED) {
                assertEq(who, whaleId, "every plain box is the order's");
                assertEq(uint256(logs[i].topics[2]), WHALE_REF, "tagged with the order's buffer and position");
                (uint256 a, uint24 lvl, uint32 sc, uint256 fl, bool up) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertLt(nOpened, 9, "bounded");
                opened[nOpened++] = Opened(a, lvl, sc, fl, up);
            } else if (t == QUEUED && uint32(uint256(logs[i].topics[1])) == whaleId) {
                (uint24 lvl, uint32 e) = abi.decode(logs[i].data, (uint24, uint32));
                assertLt(nQueued, 8, "bounded");
                qLevel[nQueued] = lvl; qEntries[nQueued++] = e;
            } else if (t == DGNRS) {
                assertEq(who, whaleId, "the DGNRS batches are the order's");
                (uint256 r, uint256 pd) = abi.decode(logs[i].data, (uint256, uint256));
                assertLt(nDgnrs, 8, "bounded");
                dReq[nDgnrs] = r; dPaid[nDgnrs++] = pd;
            } else if (t == PASSES) {
                nPasses++;
            }
        }

        assertEq(nOpened, 9, "nine boxes opened plainly on this word");
        uint24[9] memory levels = [uint24(4), 3, 2, 2, 6, 5, 49, 4, 2];
        uint32[9] memory tickets = [uint32(1977), 0, 1103, 3245, 1249, 1251, 1205, 1960, 1222];
        uint256[9] memory flips = [uint256(0), 0, 0, 0, 0, 0, 0, 0, 0];
        for (uint256 k; k < 9; k++) {
            assertEq(opened[k].amount, 135_240e12, "box amount: 0.15 ETH at 9016 bps");
            assertEq(opened[k].level, levels[k], "target level");
            assertEq(opened[k].tickets, tickets[k], "ticket variance roll");
            assertEq(opened[k].flip, flips[k], "FLIP branch");
            assertEq(opened[k].up, k == 3 || k == 4, "Bernoulli round-up");
        }
        assertEq(nQueued, 5, "five lanes queued");
        uint24[5] memory expectedLevels = [uint24(2), 4, 5, 6, 49];
        uint32[5] memory expectedEntries = [uint32(224), 152, 48, 52, 48];
        for (uint256 k; k < 5; ++k) {
            assertEq(qLevel[k], expectedLevels[k], "queued target");
            assertEq(qEntries[k], expectedEntries[k], "whole-ticket entries");
        }
        assertEq(nDgnrs, 1, "one DGNRS batch");
        assertEq(dReq[0], 243e15, "DGNRS requested");
        assertEq(dPaid[0], 243e15, "DGNRS paid in full");
        assertEq(nPasses, 0, "no craps passes rolled on this word");
    }

    /// @dev Word 68 was selected independently from the raw domain hashes to include
    ///      two flat FLIP rolls and eight plain parent boxes, with no recirculated child
    ///      box, and four flushed levels.
    function _checkWord68Box(uint256 k, uint256 a, uint24 lvl, uint32 sc, uint256 fl, bool u) internal pure {
        uint24[8] memory level = [uint24(1), 2, 4, 5, 4, 5, 22, 2];
        uint32[8] memory tickets = [uint32(3042), 1209, 0, 1349, 0, 627, 687, 0];
        uint256[8] memory flip = [uint256(0), 0, 6200, 0, 9700, 0, 0, 0];
        assertEq(a, 135_240e12, "box amount");
        assertEq(lvl, level[k], "target level");
        assertEq(sc, tickets[k], "ticket variance roll");
        assertEq(fl, flip[k], "FLIP branch");
        assertEq(u, k == 6, "Bernoulli round-up");
    }

    function test_goldensUnderWord68() public {
        address whale = _goldenFixture();
        _mineMiddayRequest(actor);
        Vm.Log[] memory logs = _fulfilAndOpen(uint256(keccak256(abi.encode("golden_word", uint256(68)))) | 1);
        assertTrue(game.boxIndexComplete(0), "opened");

        uint32 whaleId = game.walletIdOf_g3120(whale);
        uint256 nO; uint256 nQ; uint256 nP;
        for (uint256 i; i < logs.length; i++) {
            // The engine call also carries unindexed engine events (Advance, MinerWork, ...).
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 t = logs[i].topics[0];
            uint32 who = uint32(uint256(logs[i].topics[1]));
            if (t == OPENED) {
                assertEq(who, whaleId, "order's box");
                assertEq(uint256(logs[i].topics[2]), WHALE_REF, "a parent box, never a recirculated child");
                assertLt(nO, 8, "eight parent boxes");
                (uint256 a, uint24 lvl, uint32 sc, uint256 fl, bool u) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                _checkWord68Box(nO, a, lvl, sc, fl, u);
                nO++;
            } else if (t == QUEUED && uint32(uint256(logs[i].topics[1])) == whaleId) {
                assertLt(nQ, 4, "four lanes");
                (uint24 lvl, uint32 e) = abi.decode(logs[i].data, (uint24, uint32));
                uint24[4] memory lanes = [uint24(1), 2, 5, 22];
                uint32[4] memory entries = [uint32(120), 48, 76, 28];
                assertEq(lvl, lanes[nQ], "flushed lane level");
                assertEq(e, entries[nQ], "flushed lane entries");
                nQ++;
            } else if (t == PASSES) {
                nP++;
            }
        }
        assertEq(nO, 8, "eight plain parent boxes; no recirculated child");
        assertEq(nQ, 4, "four lanes flushed");
        assertEq(nP, 0, "no ordinary pass delivery");
    }
}
