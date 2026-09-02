// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {C1Viewer} from "../repro/C1BoxAutoOpen.t.sol";

/// @title LootboxOpenGoldens -- one fixed word, every reward figure a box open reports
/// @notice The box rewards are pure functions of the committed word: target level, ticket
///         variance tier, large-box FLIP variance, DGNRS pool tier, craps-pass rounding, and the
///         presale box's own roll. Their formulas live in private functions no harness can call,
///         and mutation v78 rewrote dozens of their operators without any foundry assertion
///         noticing. Under a fixed word every figure is fixed, so this opens a mixed order and a
///         presale box on one word and pins the exact figures they report.
contract LootboxOpenGoldens is DeployProtocol {
    address internal actor;
    uint256 internal constant PRESALE_BOX_CREDIT_SLOT = 17;

    bytes32 internal constant OPENED = keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant QUEUED = keccak256("EntriesQueued(address,uint24,uint32)");
    bytes32 internal constant DGNRS = keccak256("LootBoxDgnrsBatch(address,uint256,uint256)");
    bytes32 internal constant PASSES = keccak256("LootBoxCrapsPasses(address,uint32,uint32,uint24)");
    bytes32 internal constant PRESALE = keccak256("PresaleBoxOpened(address,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 internal constant REWARD = keccak256("LootBoxReward(address,uint8,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _word(uint48 index) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).rngWordFor(index);
        vm.etch(address(game), real);
    }

    /// @dev Point the permissionless open walk at `index` (cursor 0), as the auto-open repro does.
    function _parkBoxFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(56));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 m = (uint256(1) << 48) - 1;
        packed &= ~(m << (7 * 8));
        packed &= ~(m << (13 * 8));
        packed |= (uint256(index) & m) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.advanceGame() {} catch {}
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
            try game.advanceGame() {} catch {}
        }
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
        game.purchase{value: nominal + 1 ether}(actor, 400, order, bytes32(0), MintPaymentKind.DirectEth, false);

        vm.prank(actor);
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // A box that draws the ETH or WWXRP spin reports through the spin contracts instead of
        // `LootBoxOpened`, so search the word for a draw where all four boxes open plainly. The
        // word only moves the spin lottery and the ticket targets; the SIZES are the order's.
        uint256[4] memory sizes;
        bool found;
        for (uint256 w = 1; w <= 64 && !found; w++) {
            uint256 snap = vm.snapshotState();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("tier_word", w))) | 1);
            assertGt(_word(N), 0, "the word landed at the order's index");
            _parkBoxFrontier(N);
            vm.recordLogs();
            vm.prank(actor);
            uint256 opened = game.openBoxes(50);
            assertGt(opened, 0, "the walk opened the order");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 n;
            for (uint256 i; i < logs.length; i++) {
                if (logs[i].topics[0] != OPENED || logs[i].emitter != address(game)) continue;
                if (address(uint160(uint256(logs[i].topics[1]))) != actor) continue;
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

    /// @dev The figure every plainly-opened box of `who` at `index` reported (all boxes of one
    ///      single-tier order share it); zero if every box drew a spin.
    function _grantPresaleCredit(address buyer, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(buyer, uint256(PRESALE_BOX_CREDIT_SLOT)));
        uint256 existing = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(existing + amount));
    }

    struct Opened { uint256 amount; uint24 level; uint32 tickets; bool up; }

    /// @dev Word `golden_word_1`, level 0, price 0.01 ETH: an order of 6 / 3 / 2 smalls, mediums
    ///      and larges plus a 1 ETH custom, and a 0.5 ETH presale box. Eight of the twelve boxes
    ///      draw a spin and report through the spin contracts; the four that open plainly, the
    ///      one lane the flush queues, the two DGNRS batches and the presale roll are pinned to
    ///      the figure. A different figure means the reward formulas changed.
    function test_goldensUnderOneWord() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        assertEq(game.level(), 0, "golden fixture level");
        assertEq(priceWei, 0.01 ether, "golden fixture price");
        uint48 N = _idx();

        address whale = makeAddr("goldenBuyer");
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        game.purchase{value: (6 + 15 + 50) * priceWei + 1 ether + 1 ether}(whale, 400, BoxOrderLib.boOrder(6, 3, 2, 1, 1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        address pre = makeAddr("goldenPresale");
        vm.deal(pre, 5 ether);
        _grantPresaleCredit(pre, 0.5 ether);
        vm.prank(pre);
        game.buyPresaleBox{value: 0.5 ether}(pre, 0.5 ether);

        vm.prank(actor);
        game.requestLootboxRng();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256("golden_word_1")) | 1);
        assertGt(_word(N), 0, "the word landed");
        _parkBoxFrontier(N);
        vm.recordLogs();
        vm.prank(actor);
        assertGt(game.openBoxes(100), 0, "opened");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Opened[8] memory opened;
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
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            bytes32 t = logs[i].topics[0];
            address who = address(uint160(uint256(logs[i].topics[1])));
            if (t == OPENED) {
                assertEq(who, whale, "every plain box is the order's");
                (uint256 a, uint24 lvl, uint32 sc,, bool up) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertLt(nOpened, 8, "bounded");
                opened[nOpened++] = Opened(a, lvl, sc, up);
            } else if (t == QUEUED && who == whale) {
                (uint24 lvl, uint32 e) = abi.decode(logs[i].data, (uint24, uint32));
                assertLt(nQueued, 8, "bounded");
                qLevel[nQueued] = lvl; qEntries[nQueued++] = e;
            } else if (t == DGNRS) {
                assertEq(who, whale, "the DGNRS batches are the order's");
                (uint256 r, uint256 pd) = abi.decode(logs[i].data, (uint256, uint256));
                assertLt(nDgnrs, 8, "bounded");
                dReq[nDgnrs] = r; dPaid[nDgnrs++] = pd;
            } else if (t == PRESALE) {
                assertEq(who, pre, "the presale box is the presale buyer's");
                (uint256 a, uint256 fl, uint256 dg,, bool cl,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
                assertEq(a, 0.5 ether, "presale amount");
                assertFalse(cl, "not the closing box");
                presaleFlip = fl; presaleDgnrs = dg; nPresale++;
            } else if (t == PASSES) {
                nPasses++;
            }
        }

        // Four plain boxes: three smalls (9016 = 0.01 ETH at a fresh wallet's 90.16% EV) and one
        // medium; their target levels and ticket variance rolls are the word's.
        assertEq(nOpened, 4, "four boxes opened plainly on this word");
        uint24[4] memory levels = [uint24(34), 37, 2, 3];
        uint32[4] memory tickets = [uint32(44), 0, 0, 490];
        for (uint256 k; k < 4; k++) {
            assertEq(opened[k].amount, k == 3 ? 45_080_000_000_000_000 : 9_016_000_000_000_000, "box amount");
            assertEq(opened[k].level, levels[k], "target level");
            assertEq(opened[k].tickets, tickets[k], "ticket variance roll");
            assertEq(opened[k].up, k == 3, "Bernoulli round-up");
        }
        // Only the medium's 4.90 scaled tickets round up to five whole ones: twenty entries at level 3.
        assertEq(nQueued, 1, "one lane queued");
        assertEq(qLevel[0], 3, "queued at the medium's target");
        assertEq(qEntries[0], 20, "five whole tickets, four entries each");
        // Two DGNRS batches split by ETH-spin boundaries, each the small-tier pool share.
        assertEq(nDgnrs, 2, "two DGNRS batches");
        for (uint256 k; k < 2; k++) {
            assertEq(dReq[k], 16_200 ether, "DGNRS requested");
            assertEq(dPaid[k], 16_200 ether, "DGNRS paid in full from the pool");
        }
        assertEq(nPresale, 1, "the presale box opened");
        assertEq(presaleFlip, 82_100 ether, "presale FLIP roll");
        assertEq(presaleDgnrs, 0, "presale DGNRS branch not drawn");
        assertEq(nPasses, 0, "no craps passes rolled on this word");
    }

    /// @dev Word `("golden_word", 3)`, same fixture: eight plain boxes (three smalls, three mediums,
    ///      two larges — one medium rolls the 1,800 FLIP branch), five flushed lanes, two normal
    ///      craps passes placed on day 4, and the presale box's DGNRS branch.
    function test_goldensUnderWordThree() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        assertEq(game.level(), 0, "golden fixture level");
        uint48 N = _idx();
        address whale = makeAddr("goldenBuyer");
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        game.purchase{value: (6 + 15 + 50) * priceWei + 1 ether + 1 ether}(whale, 400, BoxOrderLib.boOrder(6, 3, 2, 1, 1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        address pre = makeAddr("goldenPresale");
        vm.deal(pre, 5 ether);
        _grantPresaleCredit(pre, 0.5 ether);
        vm.prank(pre);
        game.buyPresaleBox{value: 0.5 ether}(pre, 0.5 ether);
        vm.prank(actor);
        game.requestLootboxRng();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256(abi.encode("golden_word", uint256(3)))) | 1);
        _parkBoxFrontier(N);
        vm.recordLogs();
        vm.prank(actor);
        assertGt(game.openBoxes(100), 0, "opened");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[8] memory amount = [uint256(9016e12), 9016e12, 9016e12, 45080e12, 45080e12, 45080e12, 225400e12, 225400e12];
        uint24[8] memory level = [uint24(4), 2, 24, 2, 3, 3, 3, 5];
        uint32[8] memory tickets = [uint32(86), 74, 47, 0, 574, 0, 0, 1085];
        uint256[8] memory flip = [uint256(0), 0, 0, 1800 ether, 0, 0, 0, 0];
        bool[8] memory up = [true, true, true, false, true, false, false, true];
        uint24[5] memory qLevel = [uint24(2), 3, 4, 5, 24];
        uint32[5] memory qEntries = [uint32(4), 24, 4, 44, 4];
        uint256 nO; uint256 nQ; uint256 nP; uint256 nPre;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            bytes32 t = logs[i].topics[0];
            address who = address(uint160(uint256(logs[i].topics[1])));
            if (t == OPENED) {
                assertEq(who, whale, "order's box");
                assertLt(nO, 8, "eight plain boxes");
                (uint256 a, uint24 lvl, uint32 sc, uint256 fl, bool u) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertEq(a, amount[nO], "box amount");
                assertEq(lvl, level[nO], "target level");
                assertEq(sc, tickets[nO], "ticket variance roll");
                assertEq(fl, flip[nO], "FLIP branch");
                assertEq(u, up[nO], "Bernoulli round-up");
                nO++;
            } else if (t == QUEUED && who == whale) {
                assertLt(nQ, 5, "five lanes");
                (uint24 lvl, uint32 e) = abi.decode(logs[i].data, (uint24, uint32));
                assertEq(lvl, qLevel[nQ], "flushed lane level");
                assertEq(e, qEntries[nQ], "flushed lane entries");
                nQ++;
            } else if (t == PASSES) {
                assertEq(who, whale, "order's passes");
                (uint32 n, uint32 h, uint24 d) = abi.decode(logs[i].data, (uint32, uint32, uint24));
                assertEq(n, 2, "two normal passes");
                assertEq(h, 0, "no high passes");
                assertEq(d, 4, "placed on day 4");
                nP++;
            } else if (t == PRESALE) {
                assertEq(who, pre, "presale buyer");
                (uint256 a, uint256 fl, uint256 dg, uint256 ww, bool cl, uint32 pn, uint32 ph) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
                assertEq(a, 0.5 ether, "presale amount");
                assertEq(fl, 0, "presale FLIP branch not drawn");
                assertEq(dg, 3_750_000_000 ether, "presale DGNRS roll");
                assertEq(ww, 0, "presale WWXRP branch not drawn");
                assertFalse(cl, "not the closing box");
                assertEq(pn + ph, 0, "no presale passes");
                nPre++;
            }
        }
        assertEq(nO, 8, "eight boxes opened plainly");
        assertEq(nQ, 5, "five lanes flushed");
        assertEq(nP, 1, "one pass delivery");
        assertEq(nPre, 1, "the presale box opened");
    }

    /// @dev The presale roll under a given word: the same fixture, only the presale figures read.
    function _presaleUnder(uint256 w) internal returns (uint256 fl, uint256 dg, uint256 ww, uint32 pn, uint32 ph) {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        address whale = makeAddr("goldenBuyer");
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        game.purchase{value: (6 + 15 + 50) * priceWei + 1 ether + 1 ether}(whale, 400, BoxOrderLib.boOrder(6, 3, 2, 1, 1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        address pre = makeAddr("goldenPresale");
        vm.deal(pre, 5 ether);
        _grantPresaleCredit(pre, 0.5 ether);
        vm.prank(pre);
        game.buyPresaleBox{value: 0.5 ether}(pre, 0.5 ether);
        vm.prank(actor);
        game.requestLootboxRng();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256(abi.encode("golden_word", w))) | 1);
        _parkBoxFrontier(N);
        vm.recordLogs();
        vm.prank(actor);
        assertGt(game.openBoxes(100), 0, "opened");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != PRESALE) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), pre, "presale buyer");
            uint256 a; bool cl;
            (a, fl, dg, ww, cl, pn, ph) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, bool, uint32, uint32));
            assertEq(a, 0.5 ether, "presale amount");
            assertFalse(cl, "not the closing box");
            n++;
        }
        assertEq(n, 1, "the presale box opened once");
    }

    /// @dev Word `("golden_word", 12)`: the presale box takes the WWXRP branch — one whole WWXRP
    ///      prize, nothing else.
    function test_presaleGoldenWwxrpBranch() public {
        (uint256 fl, uint256 dg, uint256 ww, uint32 pn, uint32 ph) = _presaleUnder(12);
        assertEq(fl, 0, "no FLIP");
        assertEq(dg, 0, "no DGNRS");
        assertEq(ww, 1 ether, "one WWXRP prize");
        assertEq(uint256(pn) + ph, 0, "no passes");
    }

    /// @dev Word `("golden_word", 17)`: the presale box takes the craps-pass branch — four normal
    ///      day passes, nothing else.
    function test_presaleGoldenPassBranch() public {
        (uint256 fl, uint256 dg, uint256 ww, uint32 pn, uint32 ph) = _presaleUnder(17);
        assertEq(fl, 0, "no FLIP");
        assertEq(dg, 0, "no DGNRS");
        assertEq(ww, 0, "no WWXRP");
        assertEq(pn, 4, "four normal passes");
        assertEq(ph, 0, "no high passes");
    }
}
