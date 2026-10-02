// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Functional balance reconciliation for a real ordinary box's ETH spin.
/// Public buy/request/fulfill/open only; vm.load reads commitments but never changes them.
/// An independent scalar reel/score/payout oracle prices a nonzero score-six spin,
/// the live cash cap and its sDGNRS-paying child. Events are outputs under test,
/// not the source of expected rewards. Both cases hold game.level at zero
/// (the box resolver's currentLevel and denomination are level + 1 == 1).
///
/// The second purchase changes the live future pool before settlement. Frozen score
/// one is below the bonus-EV threshold, so competition for the shared bonus-EV
/// allowance, other child reward branches, boon formulas and frozen pools are NOT
/// established here. This is an accounting carrier, not a distribution/gas proof.
contract OrdinaryLootboxEthSpinAccountingTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    address private constant KEEPER = address(0xC0DE);
    uint256 private constant WORD = 7145;
    bytes32 private constant SPIN = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");
    bytes32 private constant OPENED = keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant DGNRS_BATCH = keccak256("LootBoxDgnrsBatch(address,uint256,uint256)");
    bytes32 private constant CAPPED = keccak256("PayoutCapped(address,uint256,uint256)");

    struct Expected {
        uint256 spinSeed;
        uint256 packedSpin;
        uint256 stake;
        uint256 gross;
        uint256 cash;
        uint256 recirculated;
        uint256 childAmount;
        uint256 childDgnrs;
        uint24 childTarget;
    }

    struct Balances {
        uint256 future;
        uint256 next;
        uint256 current;
        uint256 liability;
        uint256 claimable;
        uint256 eth;
        uint256 steth;
        uint256 playerEth;
        uint256 playerDgnrs;
        uint256 inventoryDgnrs;
        uint256 dgnrsSupply;
        uint256 flip;
        uint256 flipSupply;
        uint256 flipStake;
        uint256 wwxrp;
        uint256 normalPasses;
        uint256 highPasses;
        uint256[5] pools;
        uint256[51] entries;
    }

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 50 && !game.rngLocked(); ++i) {
            game.mineFlip();
        }
        assertTrue(game.rngLocked(), "bootstrap reached a real daily request");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        for (uint256 i; i < 100 && game.rngLocked(); ++i) {
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "bootstrap daily processing finished");
        game.openBoxes(type(uint256).max);
        assertEq(game.level(), 0);
        vm.deal(PLAYER, 100 ether);
    }

    function _index() private view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _order(uint48 index) private view returns (uint256) {
        bytes32 outer = keccak256(abi.encode(uint256(index), uint256(15)));
        return uint256(vm.load(address(game), keccak256(abi.encode(PLAYER, outer))));
    }

    function _buy(uint256 size) private {
        vm.prank(PLAYER);
        game.purchase{value: 0.01 ether + size}(
            PLAYER, 400, BoxOrderLib.boCustoms(1, size), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    function _hash(uint256 a, uint256 b) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(a, b)));
    }

    function _traits(uint256 entropy) private pure returns (uint32 packed) {
        for (uint256 q; q < 4; ++q) {
            uint256 color = (entropy >> (64 * q)) & 7;
            uint256 symbol = (entropy >> (64 * q + 32)) & 7;
            packed |= uint32(q * 64 + color * 8 + symbol) << (8 * q);
        }
    }

    function _variance(uint256 seed) private pure returns (uint256) {
        uint256 roll = uint24(seed >> 96) % 10_000;
        uint256[6] memory cut = [uint256(0), 100, 500, 2500, 7000, 10_000];
        uint256[5] memory lo = [uint256(40_000), 20_000, 10_000, 5923, 3600];
        uint256[5] memory hi = [uint256(65_000), 35_000, 16_000, 9923, 7200];
        for (uint256 i; i < 5; ++i) {
            if (roll < cut[i + 1]) return lo[i] + (roll - cut[i]) * (hi[i] - lo[i]) / (cut[i + 1] - cut[i] - 1);
        }
        revert("unreachable variance");
    }

    function _target(uint256 seed) private pure returns (uint24) {
        return uint16(seed) % 100 < 20 ? 6 + uint16(seed >> 24) % 46 : 1 + uint8(seed >> 16) % 5;
    }

    function _reference(uint256 future, uint256 inventory) private pure returns (Expected memory e) {
        uint256 seed =
            uint256(keccak256(abi.encode(WORD, uint256(uint160(PLAYER)), uint256(0x426f784f70656e), uint256(1))));
        require(uint16(seed >> 40) % 20 == 19, "fixture must be an ordinary ETH spin");
        // Frozen score 1 gives 90.16% box EV; 10% is reserved for the boon draw.
        uint256 budget = 0.811_44 ether * 19_678 / 10_000;
        budget = budget * (_target(seed) >= 6 ? 15_000 : 8750) / 10_000;
        e.stake = budget * _variance(seed) / 10_000;
        e.spinSeed = _hash(seed, 0x4574685370696e);
        uint256 hero = _hash(e.spinSeed, 0x446567656e4865726f) % 24;
        uint256 heroQuadrant = hero / 8;
        uint32 playerTraits = _traits(_hash(e.spinSeed, 0x446567656e506c61796572));
        playerTraits = (playerTraits & ~(uint32(7) << (8 * heroQuadrant))) | (uint32(hero & 7) << (8 * heroQuadrant));
        uint32 resultTraits = _traits(_hash(e.spinSeed, 0x446567656e526573756c74));
        uint256 score;
        uint256 gold;
        for (uint256 q; q < 4; ++q) {
            uint256 p = (playerTraits >> (8 * q)) & 63;
            uint256 r = (resultTraits >> (8 * q)) & 63;
            if (p % 8 == r % 8) score += q == heroQuadrant ? 2 : 1;
            if (p / 8 == r / 8) {
                ++score;
                if (p / 8 == 7) ++gold;
            }
        }
        require(score == 6 && gold == 0, "fixed carrier must use score six without gold");
        e.packedSpin = uint256(playerTraits) | (uint256(resultTraits) << 32) | (score << 64) | (uint256(1) << 216);
        // Score-six base is 125x; ordinary score-one ROI is 9002 bps.
        // The ETH high-score surplus factor at S6 is 1,013,556 / 1,000,000.
        e.gross = e.stake * 12_500 * 4 * (uint256(9002) * 1_000_000 + 500 * 1_013_556) / 4_000_000_000_000;
        require(e.gross > e.stake * 10, "fixture must reach the quarter-cash band");
        require(e.gross / 4 > future / 10, "live future pool cap must bind");
        e.cash = future / 10;
        e.recirculated = e.gross - e.cash;
        uint256 childSeed = _hash(_hash(e.spinSeed, 0x5265636972), uint256(uint160(PLAYER)));
        uint256 path = uint16(childSeed >> 40) % 20;
        require(path >= 8 && path < 11, "child must actually pay sDGNRS");
        e.childTarget = _target(childSeed);
        e.childAmount = e.recirculated * 9016 / 10_000;
        uint256 haircut = e.childAmount / 10;
        if (haircut > 1 ether) haircut = 1 ether;
        uint256 tier = uint24(childSeed >> 56) % 1000;
        uint256 ppm = tier < 795 ? 10 : tier < 945 ? 390 : tier < 995 ? 800 : 8000;
        e.childDgnrs = inventory * ppm * (e.childAmount - haircut) / (1_000_000 * 1 ether);
        uint256 step = 1;
        while (e.childDgnrs / step >= 1000) step *= 10;
        e.childDgnrs = e.childDgnrs / step * step;
        if (e.childDgnrs > inventory) e.childDgnrs = inventory;
    }

    function _balances() private view returns (Balances memory b) {
        b.future = game.futurePrizePoolView();
        b.next = game.nextPrizePoolView();
        b.current = game.currentPrizePoolView();
        b.liability = game.claimablePoolView();
        b.claimable = game.claimableWinningsOf(PLAYER);
        b.eth = address(game).balance;
        b.steth = mockStETH.balanceOf(address(game));
        b.playerEth = PLAYER.balance;
        b.playerDgnrs = sdgnrs.balanceOf(PLAYER);
        b.inventoryDgnrs = sdgnrs.balanceOf(address(sdgnrs));
        b.dgnrsSupply = sdgnrs.totalSupply();
        b.flip = coin.balanceOf(PLAYER);
        b.flipSupply = coin.totalSupply();
        b.flipStake = coinflip.coinflipAmount(PLAYER);
        b.wwxrp = wwxrp.balanceOf(PLAYER);
        (b.normalPasses, b.highPasses) = crapsBattle.passCreditsOf(PLAYER);
        for (uint256 i; i < 5; ++i) {
            b.pools[i] = IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool(i));
        }
        for (uint24 lvl = 1; lvl <= 51; ++lvl) {
            b.entries[lvl - 1] = game.entriesOwedView(lvl, PLAYER);
        }
    }

    function _assertEvents(Vm.Log[] memory logs, Expected memory e) private view {
        uint256 spins;
        uint256 children;
        uint256 batches;
        uint256 caps;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic != SPIN && topic != OPENED && topic != DGNRS_BATCH && topic != CAPPED) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), PLAYER, "all rewards belong to purchaser");
            if (topic == SPIN) {
                (uint64 id, uint256 packed, uint256 gross, uint256 cash) =
                    abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                assertEq(id, (uint256(1) << 63) | (uint256(2) << 60) | (e.spinSeed & ((uint256(1) << 60) - 1)));
                assertEq(packed, e.packedSpin, "independently replayed reel and score");
                assertEq(gross, e.gross, "gross payout from stake, ROI, score and gold");
                assertEq(cash, e.cash, "cash is the live pool cap");
                assertEq(gross - cash, e.recirculated, "gross reconciles cash plus child face value");
                ++spins;
            } else if (topic == OPENED) {
                assertEq(uint256(logs[i].topics[2]), 0, "direct recirculated child index");
                (uint256 amount, uint24 target, uint32 entries, uint256 flip, bool rounded) =
                    abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertEq(amount, e.childAmount, "child face value receives frozen-score EV once");
                assertEq(target, e.childTarget);
                assertEq(entries, 0);
                assertEq(flip, 0);
                assertFalse(rounded);
                ++children;
            } else if (topic == DGNRS_BATCH) {
                (uint256 requested, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(requested, e.childDgnrs, "independent live inventory reward");
                assertEq(paid, e.childDgnrs);
                ++batches;
            } else {
                (uint256 cash, uint256 recirculated) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(cash, e.cash);
                assertEq(recirculated, e.recirculated);
                ++caps;
            }
        }
        assertEq(spins, 1, "nonzero ETH-spin branch really occurred");
        assertEq(children, 1, "one recirculated child actually settled");
        assertEq(batches, 1, "one child inventory payout");
        assertEq(caps, 1, "pool-cap branch really occurred");
    }

    function _run(bool laterPurchase) private {
        uint48 index = _index();
        _buy(1 ether);
        uint256 committed = 1 | (uint256(1) << 24) | (uint256(1) << 105) | (uint256(1_000_000) << 113);
        assertEq(_order(index), committed, "real purchase committed level one, score one, one unboosted box");
        game.requestLootboxRng();
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled);
        mockVRF.fulfillRandomWords(request, WORD);
        game.mineFlip(); // publish the delivered midday word
        assertEq(_index(), (index ^ 1));
        uint256 initialFuture = game.futurePrizePoolView();
        if (laterPurchase) {
            _buy(2 ether);
            assertGt(game.futurePrizePoolView(), initialFuture, "second public purchase changed live cash inventory");
            assertGt(_order((index ^ 1)), 0, "second purchase remains an unrevealed order");
        }
        assertEq(_order(index), committed);
        assertEq(game.level(), 0, "fixed live denomination");
        uint256 nextOrder = _order((index ^ 1));
        Balances memory beforeState = _balances();
        Expected memory e = _reference(beforeState.future, beforeState.pools[2]);
        assertGt(e.cash, 0);
        assertGt(e.childDgnrs, 0);
        if (laterPurchase) assertGt(e.cash, initialFuture / 10, "live cap changed with successful second purchase");
        vm.recordLogs();
        vm.prank(KEEPER);
        assertEq(game.openBoxes(type(uint256).max), 1, "exactly one committed ordinary box consumed");
        _assertEvents(vm.getRecordedLogs(), e);
        Balances memory afterState = _balances();
        assertEq(afterState.future + e.cash, beforeState.future, "future pool cash debit");
        assertEq(afterState.liability, beforeState.liability + e.cash, "matching funded claimable liability");
        assertEq(afterState.claimable, beforeState.claimable + e.cash, "purchaser cash credit");
        assertEq(afterState.next, beforeState.next);
        assertEq(afterState.current, beforeState.current);
        assertEq(afterState.eth, beforeState.eth, "settlement only reallocates existing ETH backing");
        assertEq(afterState.steth, beforeState.steth);
        assertEq(afterState.playerEth, beforeState.playerEth);
        assertEq(afterState.playerDgnrs, beforeState.playerDgnrs + e.childDgnrs, "actual child recipient credit");
        assertEq(afterState.inventoryDgnrs + e.childDgnrs, beforeState.inventoryDgnrs, "actual token custody debit");
        assertEq(afterState.dgnrsSupply, beforeState.dgnrsSupply, "child payout transfers existing inventory");
        for (uint256 i; i < 5; ++i) {
            assertEq(
                afterState.pools[i] + (i == 2 ? e.childDgnrs : 0),
                beforeState.pools[i],
                "only Lootbox inventory pays S6 child"
            );
        }
        assertEq(afterState.flip, beforeState.flip);
        assertEq(afterState.flipSupply, beforeState.flipSupply);
        assertEq(afterState.flipStake, beforeState.flipStake);
        assertEq(afterState.wwxrp, beforeState.wwxrp);
        assertEq(afterState.normalPasses, beforeState.normalPasses);
        assertEq(afterState.highPasses, beforeState.highPasses);
        for (uint256 i; i < 51; ++i) {
            assertEq(afterState.entries[i], beforeState.entries[i]);
        }
        assertEq(game.claimableWinningsOf(KEEPER), 0);
        assertEq(sdgnrs.balanceOf(KEEPER), 0);
        assertEq(coinflip.coinflipAmount(KEEPER), 0);
        assertEq(_order(index), 0);
        assertEq(_order((index ^ 1)), nextOrder, "unrevealed second purchase survives child settlement");
        assertEq(game.openBoxes(type(uint256).max), 0, "spent parent and child cannot replay");
        assertEq(keccak256(abi.encode(_balances())), keccak256(abi.encode(afterState)), "replay has no balance effects");

        uint256 withdrawable = afterState.claimable - 1;
        vm.prank(PLAYER);
        game.claimWinnings(PLAYER);
        assertEq(PLAYER.balance, afterState.playerEth + withdrawable, "cash credit is actually withdrawable");
        assertEq(address(game).balance + withdrawable, afterState.eth, "cash withdrawal backing debit");
        assertEq(game.claimablePoolView() + withdrawable, afterState.liability);
        assertEq(game.claimableWinningsOf(PLAYER), 1, "documented claim sentinel remains");
        emit log_named_uint("gross_eth_spin", e.gross);
        emit log_named_uint("cash_eth_spin", e.cash);
        emit log_named_uint("recirculated_child_face", e.recirculated);
        emit log_named_uint("child_sdgnrs_paid", e.childDgnrs);
    }

    function testOrdinaryEthSpinCashAndChildInventoryReconcile() public {
        _run(false);
    }

    function testLaterPurchaseUsesLiveCashCapAndReconcilesChangedChild() public {
        _run(true);
    }
}
