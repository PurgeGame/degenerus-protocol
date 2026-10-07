// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @notice Functional balance reconciliation for a real ordinary box's ETH spin.
/// Public buy/request/fulfill/open only; vm.load reads commitments but never changes them.
/// An independent scalar reel/score/payout oracle prices a nonzero high-score spin,
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
    uint256 private word;
    bytes32 private constant SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    bytes32 private constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant DGNRS_BATCH = keccak256("LootBoxDgnrsBatch(uint32,uint256,uint256)");
    bytes32 private constant CAPPED = keccak256("PayoutCapped(uint32,uint256,uint256)");
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    uint256 private constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572;
    /// @dev PLAYER's committed entry position, recorded at its purchase.
    uint256 private position;

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
        _settleIdle();
        assertEq(game.level(), 0);
        vm.deal(PLAYER, 100 ether);
    }

    /// @dev Finish every read consumer of the delivered cohorts. A shut craps window the day
    ///      bound to the write buffer rides the next request, which the engine makes as mid-day
    ///      work; answer and drain it too, so a fresh request is admissible.
    function _settleIdle() private {
        for (uint256 i; i < 20; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool done) = mockVRF.pendingRequests(request);
                if (!done) mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("trailing", i))) | 2);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) return;
            if (game.advanceDue()) game.mineFlip();
        }
        revert("harness: cohorts never settled");
    }

    /// @dev One mineFlip given the smallest allowance that succeeds (bisection over snapshots).
    ///      A zero-progress call reverts, so the minimal call runs exactly the next admitted chunk
    ///      and leaves too little allowance to admit a later, larger one.
    function _stepMinimal() private {
        uint256 lo = 200_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            vm.revertToStateAndDelete(snap);
            if (ok) hi = mid;
            else lo = mid;
        }
        game.mineFlip{gas: hi}();
    }

    function _index() private view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev The stored entry; settlement never rewrites it, only the read cursor passes it.
    function _entry(uint48 index, uint256 pos) private view returns (uint256) {
        return RecyclingState.boxEntry(address(game), index, pos);
    }

    /// @dev Queried only after `index` was sealed: once a later request has sealed the other
    ///      buffer, the cohort at `index` completed first, so every entry in it is spent.
    function _spent(uint48 index, uint256 pos) private view returns (bool) {
        if (RecyclingState.readBuffer(address(game)) != index) return true;
        uint256 cursor = (uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR)))
            >> (GameSlots.BOX_CURSOR_OFFSET * 8)) & type(uint48).max;
        return cursor > pos;
    }

    /// @dev Digest of a buffer's entries (count and words).
    function _entries(uint48 index) private view returns (bytes32 digest) {
        uint256 n = RecyclingState.boxCount(address(game), index);
        digest = bytes32(n);
        for (uint256 p; p < n; ++p) digest = keccak256(abi.encode(digest, _entry(index, p)));
    }

    function _buy(uint256 size) private {
        vm.prank(PLAYER);
        game.purchase{value: 0.01 ether + size}(
            0, 400, BoxOrderLib.boCustoms(1, size), bytes32(0), MintPaymentKind.DirectEth, false
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

    /// @dev Independent oracle for the ordinary ETH-spin carrier at `word_`: `ok` is false unless the
    ///      word is an ordinary ETH spin whose win reaches the quarter-cash band, binds the live cash
    ///      cap at `future` and whose recirculated child pays sDGNRS. The box seed is the queued
    ///      entry's: H(H(QUEUED_ORDER_DOMAIN, word, buffer, position), walletId, BOX_OPEN_TAG, 1); the
    ///      recirculated child's is H(H(spinSeed, "Recir"), walletId).
    function _reference(uint256 word_, uint48 index, uint256 pos, uint32 id, uint256 future, uint256 inventory)
        private
        pure
        returns (Expected memory e, bool ok)
    {
        uint256 root = uint256(keccak256(abi.encode(QUEUED_ORDER_DOMAIN, word_, uint256(index), pos)));
        uint256 seed = uint256(keccak256(abi.encode(root, uint256(id), uint256(0x426f784f70656e), uint256(1))));
        if (uint16(seed >> 40) % 20 != 19) return (e, false);
        // Frozen score 1 gives 90.16% box EV; 10% is reserved for the boon draw.
        uint256 budget = 0.811_44 ether * 19_678 / 10_000;
        budget = budget * (_target(seed) >= 6 ? 15_000 : 8750) / 10_000;
        e.stake = budget * _variance(seed) / 10_000;
        e.spinSeed = _hash(seed, 0x4574685370696e);
        uint256 hero = Ref.randomHero(e.spinSeed);
        uint32 playerTraits = Ref.ordinary(_hash(e.spinSeed, 0x446567656e506c61796572));
        uint256 shift = (hero / 8) * 8;
        playerTraits = (playerTraits & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (hero & 7)) << shift);
        uint32 resultTraits = Ref.traits(_hash(e.spinSeed, 0x446567656e526573756c74));
        (uint256 score, uint256 wilds) = Ref.score(playerTraits, resultTraits);
        if (score < 6) return (e, false);
        e.packedSpin = uint256(playerTraits) | (uint256(resultTraits) << 32) | (score << 64) | (uint256(1) << 216);
        // Ordinary score-one ROI is 9002 bps; ETH surplus is added per score.
        uint256 base = [uint256(10_000), 62_500, 1_817_328, 23_000_000][score - 6];
        uint256 add = [uint256(240), 4600, 105_000, 22_408_400][score - 6];
        e.gross = e.stake * (base * 9002 + add * 10_000) * (4 + wilds) / 4_000_000;
        if (e.gross <= e.stake * 10 || e.gross / 4 <= future / 10) return (e, false);
        e.cash = future / 10;
        e.recirculated = e.gross - e.cash;
        uint256 childSeed = _hash(_hash(e.spinSeed, 0x5265636972), uint256(id));
        uint256 path = uint16(childSeed >> 40) % 20;
        if (path < 8 || path >= 11) return (e, false);
        e.childTarget = _target(childSeed);
        e.childAmount = e.recirculated * 9016 / 10_000;
        uint256 haircut = e.childAmount / 10;
        if (haircut > 1 ether) haircut = 1 ether;
        uint256 tier = uint24(childSeed >> 56) % 1000;
        uint256 ppm = tier < 497 ? 10 : tier < 864 ? 390 : tier < 995 ? 800 : 8000;
        e.childDgnrs = inventory * ppm * (e.childAmount - haircut) / (1_000_000 * 1 ether);
        uint256 step = 1;
        while (e.childDgnrs / step >= 1000) step *= 10;
        e.childDgnrs = e.childDgnrs / step * step;
        if (e.childDgnrs > inventory) e.childDgnrs = inventory;
        ok = e.childDgnrs > 0;
    }

    /// @dev keccak256(abi.encode(a, b, c, d)) in scratch memory: the search below runs hundreds of
    ///      thousands of candidates, and allocating for each would exhaust memory.
    function _h4(uint256 a, uint256 b, uint256 c, uint256 d) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            let p := mload(0x40)
            mstore(p, a)
            mstore(add(p, 0x20), b)
            mstore(add(p, 0x40), c)
            mstore(add(p, 0x60), d)
            r := keccak256(p, 0x80)
        }
    }

    /// @dev The first word (searched deterministically: keccak256(abi.encode("eth-spin-carrier", k)))
    ///      that yields the carrier. An allocation-free prefilter passes only first boxes that draw
    ///      the ETH spin, and of those only spins scoring six or more reach the full oracle. The live
    ///      future may still grow by the second purchase, so the cap must bind at `future + 3 ether`.
    function _carrierWord(uint48 index, uint32 id, uint256 future, uint256 inventory) private view returns (uint256 w) {
        for (uint256 k = 1;; ++k) {
            // abi.encode("eth-spin-carrier", k): string offset, k, length 16, the padded bytes.
            w = _h4(0x40, k, 16, uint256(bytes32("eth-spin-carrier")));
            uint256 seed = _h4(_h4(QUEUED_ORDER_DOMAIN, w, index, position), id, 0x426f784f70656e, 1);
            if (uint16(seed >> 40) % 20 != 19) continue;
            uint256 spinSeed = _hash(seed, 0x4574685370696e);
            uint256 hero = Ref.randomHero(spinSeed);
            uint32 playerTraits = Ref.ordinary(_hash(spinSeed, 0x446567656e506c61796572));
            uint256 shift = (hero / 8) * 8;
            playerTraits = (playerTraits & ~(uint32(0xFF) << shift)) | (uint32(0x40 | (hero & 7)) << shift);
            (uint256 score,) = Ref.score(playerTraits, Ref.traits(_hash(spinSeed, 0x446567656e526573756c74)));
            if (score < 6) continue;
            (, bool ok) = _reference(w, index, position, id, future + 3 ether, inventory);
            if (ok) return w;
        }
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

    /// @dev The FLIP a single recorded mineFlip paid its caller (MinerWork.flipReward).
    function _minerReward(Vm.Log[] memory logs) private view returns (uint256 reward) {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == MINER_WORK) {
                (,, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++seen;
            }
        }
        assertEq(seen, 1, "one MinerWork per mineFlip");
    }

    /// @dev Box results (spin or opened box) emitted by the game in a recorded window.
    function _boxResults(Vm.Log[] memory logs) private view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SPIN || logs[i].topics[0] == OPENED) ++n;
        }
    }

    function _assertEvents(Vm.Log[] memory logs, Expected memory e) private view {
        // Keep counters in memory so event decoding fits the via-IR stack.
        uint256[4] memory counts; // spins, children, inventory batches, caps
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic != SPIN && topic != OPENED && topic != DGNRS_BATCH && topic != CAPPED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), game.walletIdOf(PLAYER), "all rewards belong to purchaser");
            if (topic == SPIN) {
                (uint64 id, uint256 packed, uint256 gross, uint256 cash) =
                    abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                assertEq(id, (uint256(1) << 63) | (uint256(2) << 60) | (e.spinSeed & ((uint256(1) << 60) - 1)));
                assertEq(packed, e.packedSpin, "independently replayed reel and score");
                assertEq(gross, e.gross, "gross payout from stake, ROI, score and gold");
                assertEq(cash, e.cash, "cash is the live pool cap");
                assertEq(gross - cash, e.recirculated, "gross reconciles cash plus child face value");
                ++counts[0];
            } else if (topic == OPENED) {
                assertEq(uint256(logs[i].topics[2]), 0, "direct recirculated child index");
                (uint256 amount, uint24 target, uint32 entries, uint256 flip, bool rounded) =
                    abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertEq(amount, e.childAmount, "child face value receives frozen-score EV once");
                assertEq(target, e.childTarget);
                assertEq(entries, 0);
                assertEq(flip, 0);
                assertFalse(rounded);
                ++counts[1];
            } else if (topic == DGNRS_BATCH) {
                (uint256 requested, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(requested, e.childDgnrs, "independent live inventory reward");
                assertEq(paid, e.childDgnrs);
                ++counts[2];
            } else {
                (uint256 cash, uint256 recirculated) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(cash, e.cash);
                assertEq(recirculated, e.recirculated);
                ++counts[3];
            }
        }
        assertEq(counts[0], 1, "nonzero ETH-spin branch really occurred");
        assertEq(counts[1], 1, "one recirculated child actually settled");
        assertEq(counts[2], 1, "one child inventory payout");
        assertEq(counts[3], 1, "pool-cap branch really occurred");
    }

    function _run(bool laterPurchase) private {
        uint48 index = _index();
        position = RecyclingState.boxCount(address(game), index);
        _buy(1 ether);
        uint32 id = game.walletIdOf(PLAYER);
        uint256 committed =
            uint256(id) | (uint256(1) << 32) | (uint256(1) << 56) | (uint256(1) << 121) | (uint256(1e9) << 128);
        assertEq(_entry(index, position), committed, "real purchase committed level one, score one, one unboosted box");
        // The purchase's pending ETH clears the threshold: the engine's mid-day request.
        game.mineFlip();
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled);
        word = _carrierWord(index, id, game.futurePrizePoolView(), IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool(2)));
        mockVRF.fulfillRandomWords(request, word);
        // Publish the delivered midday word, in minimal checkpoints, up to the cohort's
        // human-box stage: the committed order is then mineFlip's next read consumer.
        for (uint256 i; i < 100 && game.nextMinerAction() != 10; ++i) _stepMinimal(); // HumanBoxes
        assertEq(game.nextMinerAction(), 10, "the committed order is the next read consumer");
        assertEq(_entry(index, position), committed, "publication alone opens nothing");
        assertFalse(_spent(index, position), "publication alone opens nothing");
        assertEq(_index(), (index ^ 1));
        uint256 initialFuture = game.futurePrizePoolView();
        if (laterPurchase) {
            uint256 nextPos = RecyclingState.boxCount(address(game), index ^ 1);
            _buy(2 ether);
            assertGt(game.futurePrizePoolView(), initialFuture, "second public purchase changed live cash inventory");
            assertEq(BoxOrderLib.boId(_entry(index ^ 1, nextPos)), id, "second purchase remains an unrevealed entry");
        }
        assertEq(_entry(index, position), committed);
        assertEq(game.level(), 0, "fixed live denomination");
        bytes32 nextEntries = _entries(index ^ 1);
        Balances memory beforeState = _balances();
        (Expected memory e, bool carrier) = _reference(word, index, position, id, beforeState.future, beforeState.pools[2]);
        assertTrue(carrier, "searched word is the ordinary ETH-spin carrier");
        assertGt(e.cash, 0);
        assertGt(e.childDgnrs, 0);
        if (laterPurchase) assertGt(e.cash, initialFuture / 10, "live cap changed with successful second purchase");
        uint256 keeperFlip = coinflip.coinflipAmount(KEEPER);
        vm.recordLogs();
        vm.prank(KEEPER);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // One parent spin and its one recirculated child: exactly one committed ordinary box consumed.
        _assertEvents(logs, e);
        uint256 keeperReward = _minerReward(logs);
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
                "only Lootbox inventory pays the child"
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
        assertEq(coinflip.coinflipAmount(KEEPER), keeperFlip + keeperReward, "the keeper's only FLIP is its measured miner reward");
        assertTrue(_spent(index, position), "the committed entry settled");
        assertEq(_entry(index, position), committed, "settlement never rewrites the entry");
        assertEq(_entries(index ^ 1), nextEntries, "unrevealed second purchase survives child settlement");
        // Replay probe: whatever the engine does next (or NoWork / a pending word), it opens nothing.
        vm.recordLogs();
        vm.prank(KEEPER);
        (bool replayed,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
        replayed;
        assertEq(_boxResults(vm.getRecordedLogs()), 0, "spent parent and child cannot replay");
        assertEq(keccak256(abi.encode(_balances())), keccak256(abi.encode(afterState)), "replay has no balance effects");

        uint256 withdrawable = afterState.claimable - 1;
        vm.prank(PLAYER);
        game.claimWinnings(0);
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
