// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title LootboxOpenGoldens -- one fixed word, every reward figure a box open reports
/// @notice The box rewards are pure functions of the committed word: target level, ticket
///         variance tier, large-box FLIP variance, DGNRS pool tier, craps-pass rounding, and the
///         presale box's own roll. Their formulas live in private functions no harness can call,
///         and mutation v78 rewrote dozens of their operators without any foundry assertion
///         noticing. Under a fixed word every figure is fixed, so this opens a mixed order and a
///         presale box on one word and pins the exact figures they report.
contract LootboxOpenGoldens is DeployProtocol {
    address internal actor;
    uint256 internal constant PRESALE_BOX_CREDIT_SLOT = GameSlots.PRESALE_BOX_CREDIT;

    bytes32 internal constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant QUEUED = keccak256("EntriesQueued(uint32,uint24,uint32)");
    bytes32 internal constant DGNRS = keccak256("LootBoxDgnrsBatch(uint32,uint256,uint256)");
    bytes32 internal constant PASSES = keccak256("LootBoxCrapsPasses(uint32,uint32,uint32,uint24)");
    bytes32 internal constant PRESALE = keccak256("PresaleBoxOpened(uint32,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
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
        (, , , , uint256 priceWei) = game.purchaseInfo();
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

    function test_tiersOpenAtOneFiveAndTwentyFivePrices() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();

        // One of each tier, plus a one-ETH custom box so the pending ETH clears the mid-day
        // request threshold (the tiers alone are 31 ticket prices).
        uint256 order = BoxOrderLib.boOrder(1, 1, 1, 1, 1 ether);
        uint256 nominal = 31 * priceWei + 1 ether;
        vm.prank(actor);
        game.purchase{value: nominal + 1 ether}(0, 400, order, bytes32(0), MintPaymentKind.DirectEth, false);

        uint256 reqId = _mineMiddayRequest(actor);

        // A box that draws the ETH or WWXRP spin reports through the spin contracts instead of
        // `LootBoxOpened`, so search the word for a draw where all four boxes open plainly. The
        // word only moves the spin lottery and the ticket targets; the SIZES are the order's.
        uint256[4] memory sizes;
        bool found;
        for (uint256 w = 1; w <= 64 && !found; w++) {
            uint256 snap = vm.snapshotState();
            assertEq(mockVRF.lastRequestId(), reqId, "the mid-day request is the pending one");
            Vm.Log[] memory logs = _fulfilAndOpen(uint256(keccak256(abi.encode("tier_word", w))) | 1);
            assertGt(_word(N), 0, "the word landed at the order's index");
            assertTrue(game.boxIndexComplete(N), "the walk opened the order");
            uint256 n;
            for (uint256 i; i < logs.length; i++) {
                if (logs[i].topics[0] != OPENED || logs[i].emitter != address(game)) continue;
                if (uint32(uint256(logs[i].topics[1])) != game.walletIdOf(actor)) continue;
                (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                if (n < 4) sizes[n] = amount;
                n++;
            }
            assertLe(n, 4, "never more than the four boxes ordered");
            if (n == 4) found = true;
            else vm.revertToState(snap);
        }
        assertTrue(found, "some word opens all four boxes without a spin");
        // Sort; the custom (one ETH) is the largest, the three tiers sit below it.
        for (uint256 a; a < 4; a++) {
            for (uint256 b = a + 1; b < 4; b++) {
                if (sizes[b] < sizes[a]) (sizes[a], sizes[b]) = (sizes[b], sizes[a]);
            }
        }
        // `amount` is the box's EV-scaled figure: the wallet's EV, boost and adjustment rates ride
        // every tier alike, so the four figures keep the order's size ratios to within flooring.
        assertGt(sizes[0], 0, "the small box opened with a size");
        assertApproxEqAbs(sizes[1], 5 * sizes[0], 8, "the medium box is five small boxes");
        assertApproxEqAbs(sizes[2], 25 * sizes[0], 32, "the large box is twenty-five small boxes");
        assertApproxEqAbs(sizes[3], (1 ether / priceWei) * sizes[0], 1 ether / priceWei + 1, "the custom box is its own size in small boxes");
    }

    function _grantPresaleCredit(address buyer, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(buyer)), uint256(PRESALE_BOX_CREDIT_SLOT)));
        uint256 existing = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(existing + amount));
    }

    struct Opened { uint256 amount; uint24 level; uint32 tickets; uint256 flip; bool up; }

    /// @dev Event tags of the fixture's two entries: QUEUED_ENTRY_TAG | position << 1 | buffer.
    uint48 internal constant QUEUED_ENTRY_TAG = uint48(1) << 46;
    uint48 internal constant WHALE_REF = QUEUED_ENTRY_TAG; // buffer 0, position 0
    uint48 internal constant PRESALE_REF = QUEUED_ENTRY_TAG | (uint48(1) << 1); // buffer 0, position 1

    /// @dev The golden fixture: on buffer 0, the whale's mixed order (6 small, 3 medium, 2 large and
    ///      one 1-ETH custom box) is entry 0 and a 0.5-ETH presale-only purchase is entry 1. Every
    ///      queued seed is H(H(QUEUED_ORDER_DOMAIN, word, buffer, position), walletId, tag, n), so the
    ///      pinned figures belong to these wallet IDs and positions; the fixture asserts both.
    function _goldenFixture() internal returns (address whale, address pre) {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        assertEq(game.level(), 0, "golden fixture level");
        assertEq(priceWei, 0.01 ether, "golden fixture price");
        assertEq(_idx(), 0, "golden fixture tag");
        assertEq(RecyclingState.boxCount(address(game), 0), 0, "golden fixture: empty buffer");
        whale = makeAddr("goldenBuyer");
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        game.purchase{value: (6 + 15 + 50) * priceWei + 1 ether + 1 ether}(0, 400, BoxOrderLib.boOrder(6, 3, 2, 1, 1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        pre = makeAddr("goldenPresale");
        vm.deal(pre, 5 ether);
        _giveWalletId(pre); // presale credit is keyed by wallet ID
        _grantPresaleCredit(pre, 0.5 ether);
        vm.prank(pre);
        game.buyPresaleBox{value: 0.5 ether}(0, 0.5 ether);
        assertEq(RecyclingState.boxCount(address(game), 0), 2, "golden fixture: two entries");
        assertEq(BoxOrderLib.boId(RecyclingState.boxEntry(address(game), 0, 0)), 5, "golden fixture: whale wallet ID 5 at position 0");
        assertEq(BoxOrderLib.boId(RecyclingState.boxEntry(address(game), 0, 1)), 6, "golden fixture: presale wallet ID 6 at position 1");
        assertEq(BoxOrderLib.boPresaleWei(RecyclingState.boxEntry(address(game), 0, 1)), 0.5 ether, "golden fixture: presale-only entry");
    }

    /// @dev Fixed word ("golden_word", 28): nine plain boxes, three queued levels, one DGNRS batch
    ///      and the presale DGNRS branch. Values are pinned below.
    function test_goldensUnderOneWord() public {
        (address whale, address pre) = _goldenFixture();
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
        uint256 presaleFlip;
        uint256 presaleDgnrs;
        uint256 nPresale;
        uint256 nPasses;
        uint32 whaleId = game.walletIdOf(whale);
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
            } else if (t == PRESALE) {
                assertEq(who, game.walletIdOf(pre), "the presale box is the presale buyer's");
                assertEq(uint256(logs[i].topics[2]), PRESALE_REF, "tagged with the presale entry's position");
                (uint256 a, uint256 fl, uint256 dg,, bool cl,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
                assertEq(a, 0.5 ether, "presale amount");
                assertFalse(cl, "not the closing box");
                presaleFlip = fl; presaleDgnrs = dg; nPresale++;
            } else if (t == PASSES) {
                nPasses++;
            }
        }

        assertEq(nOpened, 9, "nine boxes opened plainly on this word");
        uint24[9] memory levels = [uint24(5), 4, 4, 3, 3, 2, 4, 19, 2];
        uint32[9] memory tickets = [uint32(47), 150, 0, 0, 308, 0, 1096, 0, 0];
        uint256[9] memory flips = [uint256(0), 0, 560, 0, 0, 0, 0, 0, 0];
        uint256[9] memory amounts = [uint256(9016e12), 9016e12, 9016e12, 9016e12, 45080e12, 45080e12, 45080e12, 225400e12, 225400e12];
        for (uint256 k; k < 9; k++) {
            assertEq(opened[k].amount, amounts[k], "box amount");
            assertEq(opened[k].level, levels[k], "target level");
            assertEq(opened[k].tickets, tickets[k], "ticket variance roll");
            assertEq(opened[k].flip, flips[k], "FLIP branch");
            assertEq(opened[k].up, k == 0 || k == 6, "Bernoulli round-up");
        }
        assertEq(nQueued, 3, "three lanes queued");
        uint24[3] memory expectedLevels = [uint24(3), 4, 5];
        uint32[3] memory expectedEntries = [uint32(12), 48, 4];
        for (uint256 k; k < 3; ++k) {
            assertEq(qLevel[k], expectedLevels[k], "queued target");
            assertEq(qEntries[k], expectedEntries[k], "whole-ticket entries");
        }
        assertEq(nDgnrs, 1, "one DGNRS batch");
        assertEq(dReq[0], 32_902_300e12, "DGNRS requested");
        assertEq(dPaid[0], 32_902_300e12, "DGNRS paid in full");
        assertEq(nPresale, 1, "the presale box opened");
        assertEq(presaleFlip, 0, "presale FLIP branch not drawn");
        assertEq(presaleDgnrs, 3_750_000_000e12, "presale DGNRS roll");
        assertEq(nPasses, 0, "no craps passes rolled on this word");
    }

    /// @dev Second fixed word: eight plain parent boxes (tickets, flat FLIP and large-box FLIP), no
    ///      recirculated child box, two flushed levels, and the presale FLIP branch kept as coinflip
    ///      credit.
    function test_goldensUnderWordThree() public {
        (address whale, address pre) = _goldenFixture();
        _mineMiddayRequest(actor);
        Vm.Log[] memory logs = _fulfilAndOpen(uint256(keccak256(abi.encode("golden_word", uint256(3)))) | 1);
        assertTrue(game.boxIndexComplete(0), "opened");

        uint256[8] memory amount = [uint256(9016e12), 9016e12, 9016e12, 9016e12, 9016e12, 45080e12, 45080e12, 901600e12];
        uint24[8] memory level = [uint24(5), 5, 3, 3, 18, 3, 9, 2];
        uint32[8] memory tickets = [uint32(0), 42, 0, 119, 47, 0, 263, 0];
        uint256[8] memory flip = [uint256(0), 0, 618, 0, 0, 3800, 0, 67700];
        bool[8] memory up = [false, false, false, true, false, false, false, false];
        uint24[2] memory qLevel = [uint24(3), 9];
        uint32[2] memory qEntries = [uint32(8), 8];
        uint32 whaleId = game.walletIdOf(whale);
        uint256 nO; uint256 nQ; uint256 nP; uint256 nPre;
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
                assertEq(a, amount[nO], "box amount");
                assertEq(lvl, level[nO], "target level");
                assertEq(sc, tickets[nO], "ticket variance roll");
                assertEq(fl, flip[nO], "FLIP branch");
                assertEq(u, up[nO], "Bernoulli round-up");
                nO++;
            } else if (t == QUEUED && uint32(uint256(logs[i].topics[1])) == whaleId) {
                assertLt(nQ, 2, "two lanes");
                (uint24 lvl, uint32 e) = abi.decode(logs[i].data, (uint24, uint32));
                assertEq(lvl, qLevel[nQ], "flushed lane level");
                assertEq(e, qEntries[nQ], "flushed lane entries");
                nQ++;
            } else if (t == PASSES) {
                nP++;
            } else if (t == PRESALE) {
                assertEq(who, game.walletIdOf(pre), "presale buyer");
                assertEq(uint256(logs[i].topics[2]), PRESALE_REF, "the presale entry's tag");
                (uint256 a, uint256 fl, uint256 dg, uint256 ww, bool cl, uint32 pn, uint32 ph) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
                assertEq(a, 0.5 ether, "presale amount");
                assertEq(fl, 151_500, "presale FLIP branch kept as coinflip credit");
                assertEq(dg, 0, "presale DGNRS branch not drawn");
                assertEq(ww, 0, "presale WWXRP branch not drawn");
                assertFalse(cl, "not the closing box");
                assertEq(pn, 0, "no presale normal passes");
                assertEq(ph, 0, "no presale high passes");
                nPre++;
            }
        }
        assertEq(nO, 8, "eight plain parent boxes; no recirculated child");
        assertEq(nQ, 2, "two lanes flushed");
        assertEq(nP, 0, "no ordinary pass delivery");
        assertEq(nPre, 1, "the presale box opened");
    }

    /// @dev The presale roll under a given word: the same fixture, only the presale figures read.
    function _presaleUnder(uint256 w) internal returns (uint256 fl, uint256 dg, uint256 ww, uint32 pn, uint32 ph) {
        (, address pre) = _goldenFixture();
        _mineMiddayRequest(actor);
        Vm.Log[] memory logs = _fulfilAndOpen(uint256(keccak256(abi.encode("golden_word", w))) | 1);
        assertTrue(game.boxIndexComplete(0), "opened");
        uint256 n;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != PRESALE) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf(pre), "presale buyer");
            assertEq(uint256(logs[i].topics[2]), PRESALE_REF, "the presale entry's tag");
            uint256 a; bool cl;
            (a, fl, dg, ww, cl, pn, ph) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
            assertEq(a, 0.5 ether, "presale amount");
            assertFalse(cl, "not the closing box");
            n++;
        }
        assertEq(n, 1, "the presale box opened once");
    }

    /// @dev Word `("golden_word", 12)`: the presale box takes the WWXRP branch — one whole WWXRP
    ///      prize (the event reports it before WWXRP's mint scale), nothing else.
    function test_presaleGoldenWwxrpBranch() public {
        (uint256 fl, uint256 dg, uint256 ww, uint32 pn, uint32 ph) = _presaleUnder(12);
        assertEq(fl, 0, "no FLIP");
        assertEq(dg, 0, "no DGNRS");
        assertEq(ww, 1, "one WWXRP prize");
        assertEq(uint256(pn) + ph, 0, "no passes");
    }

    /// @dev Word `("golden_word", 4)`: the presale box takes the craps-pass branch — five normal
    ///      day passes (24,800-FLIP units), nothing else.
    function test_presaleGoldenPassBranch() public {
        (uint256 fl, uint256 dg, uint256 ww, uint32 pn, uint32 ph) = _presaleUnder(4);
        assertEq(fl, 0, "no FLIP");
        assertEq(dg, 0, "no DGNRS");
        assertEq(ww, 0, "no WWXRP");
        assertEq(pn, 5, "five normal passes");
        assertEq(ph, 0, "no high passes");
    }
}
