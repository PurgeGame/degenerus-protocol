// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {QueueHost} from "../helpers/BoxQueueHost.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";

/// @dev The Lootbox module's own score codec, the one owner of the queued entry word.
contract ScoreCodeHarness is DegenerusGameLootboxModule {
    function code(uint256 score) external pure returns (uint256) { return _scoreCode(score); }
    function decode(uint256 c) external pure returns (uint256) { return _scoreFromCode(c); }
}

/// @title LootboxCompactQueue -- three 85-bit orders per queue word
/// @notice Lane packing, buffer reuse at every short count, resumption at every lane, distinct
///         roots for identical orders sharing a word, the 12-bit score code, grant flooring and
///         the purchase-time preset value.
contract LootboxCompactQueueTest is DeployProtocol {
    QueueHost internal host;
    ScoreCodeHarness internal codec;
    address internal alice;
    address internal bob;

    bytes32 internal constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant BOX_BUY = keccak256("LootBoxBuy(uint32,uint48,uint32,uint256)");
    uint256 internal constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572;
    uint256 internal constant BOX_OPEN_TAG = 0x426f784f70656e;
    uint256 internal constant BOX_BOON_TAG = 0x426f78426f6f6e;
    uint48 internal constant QUEUED_ENTRY_TAG = uint48(1) << 46;
    uint256 internal constant WORD = 0xc0a1e5ce00000000000000000000000000000000000000000000000000c0ffee;
    uint256 internal constant ALLOWANCE = 25_000_000;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(QueueHost).runtimeCode);
        host = QueueHost(payable(address(game)));
        codec = new ScoreCodeHarness();
        alice = makeAddr("compactAlice");
        bob = makeAddr("compactBob");
        vm.deal(alice, 1e9 ether);
        vm.deal(bob, 1e9 ether);
        vm.deal(address(game), 10_000 ether);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _id(address who) internal view returns (uint32) { return host.walletIdOf(who); }

    function _buy(address who, uint256 boxOrder) internal returns (uint48 buffer, uint256 position) {
        buffer = host.writeBuffer();
        position = host.boxWriteCount();
        (, uint256 cost) = host.decode(boxOrder, host.activeLevel());
        vm.prank(who);
        host.purchase{value: cost}(0, 0, boxOrder, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(host.boxWriteCount(), position + 1, "one purchase, one entry");
    }

    function _drain(uint256 word) internal returns (Vm.Log[] memory logs) {
        host.sealAndPublish(word);
        vm.recordLogs();
        assertTrue(host.work(ALLOWANCE).done, "drain completes");
        logs = vm.getRecordedLogs();
    }

    /// @dev Return the write buffer to `buffer` with every earlier cohort settled.
    function _cycleTo(uint48 buffer) internal {
        for (uint256 i; i < 2 && host.writeBuffer() != buffer; ++i) {
            host.sealAndPublish(WORD ^ (i + 11));
            assertTrue(host.work(ALLOWANCE).done);
        }
        assertEq(host.writeBuffer(), buffer);
    }

    function _ref(uint48 buffer, uint256 position) internal pure returns (uint48) {
        return QUEUED_ENTRY_TAG | (uint48(position) << 1) | buffer;
    }

    function _root(uint256 word, uint48 buffer, uint256 position) internal pure returns (uint256) {
        return EntropyLib.hash4(QUEUED_ORDER_DOMAIN, word, buffer, position);
    }

    function _rollOf(uint256 seed, uint24 currentLevel) internal pure returns (bool emits, uint24 target) {
        uint256 rangeRoll = uint16(seed) % 100;
        target = rangeRoll < 20
            ? currentLevel + uint24(uint16(seed >> 24) % 46 + 5)
            : currentLevel + uint24(uint8(seed >> 16) % 5);
        uint256 path = uint16(seed >> 40) % 20;
        emits = path <= 10 || path == 14 || path == 15 || path == 16;
    }

    function _assertSeeded(Vm.Log[] memory logs, uint48 tag, uint256 rootWord, uint32 id, uint256 boxes)
        internal
        returns (bytes32 sequence)
    {
        uint24 cur = host.level() + 1;
        uint24[] memory expected = new uint24[](boxes);
        uint256 en;
        for (uint256 i = 1; i <= boxes; ++i) {
            uint256 seed = EntropyLib.hash4(rootWord, uint256(id), BOX_OPEN_TAG, i);
            sequence = keccak256(abi.encode(sequence, seed));
            (bool emits, uint24 target) = _rollOf(seed, cur);
            if (emits) expected[en++] = target;
        }
        uint256 sn;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED && uint256(logs[i].topics[2]) == tag) {
                (, uint24 futureLevel,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertLt(sn, en, "no more opened boxes than predicted");
                assertEq(futureLevel, expected[sn], "box target level follows its predicted seed");
                ++sn;
            }
        }
        assertGt(en, 0, "fixture rolls at least one non-spin box");
        assertEq(sn, en, "LootBoxOpened count matches the predicted non-spin boxes");
    }

    function _entry(uint32 id, uint256 units, uint256 code, uint256 boost, uint256 qty, bool distress)
        internal
        pure
        returns (uint256)
    {
        return BoxOrderLib.boEntry(id, units, code, boost, qty, distress);
    }

    // =========================================================================
    // Score code
    // =========================================================================

    function _checkScore(uint256 score) internal {
        uint256 c = codec.code(score);
        uint256 d = codec.decode(c);
        assertLe(c, 4039, "code never above 4,039");
        assertEq(c, BoxOrderLib.scoreCode(score), "test mirror agrees with the module");
        assertEq((host.scoreWord(score) >> 53) & 0xFFF, c, "applyBoxOrderScore stores the module's code");
        assertEq(host.scoreWord(score) & ~(uint256(0xFFF) << 53), 0, "the code touches no other field");
        uint256 clamped = score > 30_000 ? 30_000 : score;
        assertLe(d, clamped, "never decodes above the clamped input");
        assertLe(clamped - d, 13, "at most 13 points low");
        if (clamped <= 2042 || clamped == 30_000) assertEq(d, clamped, "exact through 2,042 and at the cap");
    }

    function test_ScoreCode_ListedValues() public {
        uint256[19] memory v = [uint256(0), 59, 60, 61, 399, 400, 500, 1200, 2041, 2042, 2043, 2055, 2056, 4095,
            4096, 29_999, 30_000, 30_001, 65_534];
        for (uint256 i; i < v.length; ++i) _checkScore(v[i]);
        assertEq(codec.code(30_000), 4039);
        assertEq(codec.decode(4039), 30_000);
        assertEq(codec.code(2055), 2042, "2,055 floors to the last exact code");
        assertEq(codec.code(2056), 2043);
        assertEq(codec.decode(2043), 2056);
        assertEq(codec.code(65_534), 4039, "above the cap clamps, never wraps");
        assertEq(codec.code(4096), 2188, "4,096 does not wrap to a low code");
    }

    function testFuzz_ScoreCode_RoundTrip(uint256 score) public {
        _checkScore(bound(score, 0, 65_534));
    }

    function testFuzz_ScoreCode_Monotone(uint256 a, uint256 b) public view {
        a = bound(a, 0, 65_534);
        b = bound(b, a, 65_534);
        assertLe(codec.code(a), codec.code(b), "code is monotone");
        assertLe(codec.decode(codec.code(a)), codec.decode(codec.code(b)), "decode is monotone");
    }

    /// @notice The opener uses the DECODED score: a grant frozen at 2,055 opens at the
    ///         multiplier of 2,042, an independent immediate box at its own exact score.
    function test_ScoreCode_OpenerUsesDecodedScore() public {
        _buy(alice, BoxOrderLib.boSmalls(1)); // registers alice
        host.grant(alice, 0.5 ether, 2055, false, 10);
        uint48 b = host.writeBuffer();
        uint256 p = host.boxWriteCount() - 1;
        assertEq(BoxOrderLib.boScore(host.entryAt(b, p)), 2042);
        Vm.Log[] memory logs = _drain(WORD);
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED && uint256(logs[i].topics[2]) == _ref(b, p)) {
                (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                uint256 mult = host.evMultiplier(2042);
                if (mult <= 10_000) assertEq(amount, 0.05 ether * mult / 10_000, "box scaled by the decoded score");
                ++seen;
            }
        }
        assertGt(seen, 0, "a box opened plainly");
    }

    // =========================================================================
    // Lane packing
    // =========================================================================

    /// @notice Three independently generated orders appended at lanes 0, 1 and 2 of one word
    ///         read back exactly, never alter a neighbor, and never set bit 255.
    function testFuzz_Packing_ThreeLanesRoundTrip(uint256 seed) public {
        uint48 b = host.writeBuffer();
        uint256[3] memory e;
        for (uint256 i; i < 3; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            e[i] = _entry(
                uint32(bound(r, 1, type(uint32).max)),
                bound(r >> 32, 1, 2_000_000),
                bound(r >> 64, 0, 4039),
                bound(r >> 80, 0, 2500),
                bound(r >> 96, 1, 100),
                (r >> 112) & 1 == 1
            );
            host.appendEntry(e[i], 0);
            for (uint256 j; j <= i; ++j) {
                assertEq(host.entryAt(b, j), e[j], "every appended lane reads back unchanged");
                assertEq(RecyclingState.boxEntry(address(game), b, j), e[j], "raw lane reader agrees");
            }
        }
        uint256 raw = uint256(vm.load(address(game), RecyclingState.boxWordSlot(b, 0)));
        assertEq(raw >> 255, 0, "bit 255 stays zero");
        assertEq(raw, e[0] | (e[1] << 85) | (e[2] << 170), "the word is exactly the three lanes");
        assertEq(BoxOrderLib.boCount(e[1]), (raw >> (85 + 77)) & 0x7F);
    }

    /// @notice Buffer reuse at counts 0, 1, 2, 3, 4, 6 and 7 after a longer (7) and a shorter (1)
    ///         prior cohort: the first lane of each word erases its stale upper lanes, the entries
    ///         read back exactly, and settlement stops at the count.
    function test_Reuse_EveryShortCountAfterLongerAndShorterCohorts() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        _buy(bob, BoxOrderLib.boSmalls(1));
        host.sealAndPublish(WORD);
        assertTrue(host.work(ALLOWANCE).done);
        uint32[2] memory ids = [_id(alice), _id(bob)];
        uint256[7] memory counts = [uint256(0), 1, 2, 3, 4, 6, 7];
        uint256[2] memory priors = [uint256(7), 1];
        for (uint256 pi; pi < 2; ++pi) {
            for (uint256 ci; ci < counts.length; ++ci) {
                uint256 snap = vm.snapshotState();
                uint48 b = host.writeBuffer();
                for (uint256 i; i < priors[pi]; ++i) host.appendEntry(_entry(ids[i % 2], 50 + i, 7, 0, 1, false), 0);
                host.sealAndPublish(WORD ^ 1);
                assertTrue(host.work(ALLOWANCE).done, "prior cohort drains");
                _cycleTo(b);
                uint256 n = counts[ci];
                for (uint256 i; i < n; ++i) host.appendEntry(_entry(ids[(i + 1) % 2], 900 + i, 3, 0, 2, false), 0);
                for (uint256 i; i < n; ++i) {
                    assertEq(host.entryAt(b, i), _entry(ids[(i + 1) % 2], 900 + i, 3, 0, 2, false), "fresh entry");
                }
                if (n % 3 != 0) {
                    uint256 lastWord = uint256(vm.load(address(game), RecyclingState.boxWordSlot(b, n - 1)));
                    for (uint256 lane = n % 3; lane < 3; ++lane) {
                        assertEq((lastWord >> (lane * 85)) & BoxOrderLib.ENTRY_MASK, 0, "stale upper lane erased");
                    }
                }
                Vm.Log[] memory logs = _drain(WORD ^ 2);
                (uint256 readCount, uint256 cursor, bool complete) = host.readState();
                assertEq(readCount, n);
                assertEq(cursor, n, "settlement stops at the count");
                assertTrue(complete);
                for (uint256 i; i < logs.length; ++i) {
                    if (logs[i].topics.length != 3 || logs[i].topics[0] != OPENED) continue;
                    uint256 tag = uint256(logs[i].topics[2]);
                    if (tag & QUEUED_ENTRY_TAG == 0) continue;
                    uint256 position = (tag & (QUEUED_ENTRY_TAG - 1)) >> 1;
                    assertLt(position, n, "no stale order beyond the count opens");
                    assertEq(uint32(uint256(logs[i].topics[1])), ids[(position + 1) % 2], "the fresh order's owner");
                }
                assertTrue(vm.revertToState(snap));
            }
        }
    }

    // =========================================================================
    // Resumption at every lane
    // =========================================================================

    function _openedDigest(Vm.Log[] memory logs) internal pure returns (bytes32 digest) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == OPENED) {
                digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
            }
        }
    }

    /// @notice Seven orders over three words, settled one order per call: every call starts at the
    ///         next lane (0, 1, 2, 0, ...), the cursor advances exactly one logical order, and the
    ///         opened boxes equal one uninterrupted drain.
    function test_Resume_EveryLaneBoundary() public {
        for (uint256 i; i < 7; ++i) _buy(i % 2 == 0 ? alice : bob, BoxOrderLib.boCustoms(3, 0.5 ether));
        host.sealAndPublish(WORD);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        assertTrue(host.work(ALLOWANCE).done);
        bytes32 whole = _openedDigest(vm.getRecordedLogs());
        assertTrue(vm.revertToState(snap));

        uint256 step = GasBounds.HUMAN_ENTRY_GAS + 3 * GasBounds.HUMAN_BOX_GAS + GasBounds.HUMAN_TAIL_GAS
            + MineFlipGas.CHECK_RESERVE + 50_000;
        vm.recordLogs();
        for (uint256 call = 1; call <= 7; ++call) {
            host.work(step);
            (, uint256 cursor,) = host.readState();
            assertEq(cursor, call, "one logical order per bounded call, resuming at the next lane");
        }
        assertTrue(host.work(ALLOWANCE).done, "completion");
        assertEq(_openedDigest(vm.getRecordedLogs()), whole, "paused settlement opens exactly the same boxes");
    }

    // =========================================================================
    // Identical orders in one word
    // =========================================================================

    /// @notice Three identical orders from one wallet share one physical word, yet each keeps its
    ///         logical position: distinct order roots, boon seeds and box seed sequences.
    function test_Seeds_ThreeIdenticalOrdersOneWord() public {
        uint256 order = BoxOrderLib.boCustoms(10, 1 ether);
        (uint48 b, uint256 p0) = _buy(alice, order);
        assertEq(p0, 0, "a fresh word");
        _buy(alice, order);
        _buy(alice, order);
        assertEq(host.entryAt(b, 0), host.entryAt(b, 1));
        assertEq(host.entryAt(b, 1), host.entryAt(b, 2), "three identical entries");
        Vm.Log[] memory logs = _drain(WORD);
        uint32 id = _id(alice);
        bytes32[3] memory seq;
        uint256[3] memory boon;
        for (uint256 p; p < 3; ++p) {
            seq[p] = _assertSeeded(logs, _ref(b, p), _root(WORD, b, p), id, 10);
            boon[p] = EntropyLib.hash4(_root(WORD, b, p), uint256(id), BOX_BOON_TAG, b);
        }
        assertTrue(_root(WORD, b, 0) != _root(WORD, b, 1) && _root(WORD, b, 1) != _root(WORD, b, 2));
        assertTrue(seq[0] != seq[1] && seq[1] != seq[2] && seq[0] != seq[2], "distinct box seed sequences");
        assertTrue(boon[0] != boon[1] && boon[1] != boon[2] && boon[0] != boon[2], "distinct boon seeds");
    }

    // =========================================================================
    // Grants
    // =========================================================================

    function _lastEntry() internal view returns (uint256) {
        return host.entryAt(host.writeBuffer(), host.boxWriteCount() - 1);
    }

    /// @notice Grants floor per box to whole 0.001 ETH: 0.024 and 0.012 ETH are exact, 0.0249
    ///         stores 0.024 while LootBoxBuy and the pending lane keep the funded 0.0249; a
    ///         nonzero grant below the 0.01 ETH purchase minimum still queues.
    function test_Grants_UnitFlooring() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.grant(alice, 0.024 ether, 100, false, 0);
        assertEq(BoxOrderLib.boSizeWei(_lastEntry()), 0.024 ether);
        assertEq(BoxOrderLib.boCount(_lastEntry()), 1, "count 0 stores one box");
        host.grant(alice, 0.012 ether, 100, false, 1);
        assertEq(BoxOrderLib.boSizeWei(_lastEntry()), 0.012 ether);

        uint256 pending = host.pendingMilliEth();
        uint48 b = host.writeBuffer();
        uint256 p = host.boxWriteCount();
        vm.recordLogs();
        host.grant(alice, 0.0249 ether, 100, false, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(BoxOrderLib.boSizeWei(host.entryAt(b, p)), 0.024 ether, "0.0249 floors to 0.024");
        assertEq(host.pendingMilliEth(), pending + 24, "pending lane banks the funded amount's milli-ETH");
        bool sawBuy;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == BOX_BUY) {
                (uint32 position, uint256 amount) = abi.decode(logs[i].data, (uint32, uint256));
                assertEq(position, p);
                assertEq(amount, 0.0249 ether, "LootBoxBuy keeps the original amount");
                sawBuy = true;
            }
        }
        assertTrue(sawBuy);

        host.grant(alice, 0.005 ether, 100, false, 0);
        assertEq(BoxOrderLib.boSizeWei(_lastEntry()), 0.005 ether, "a sub-0.01 grant still queues");
    }

    /// @notice A grant flooring to zero per box appends nothing and consumes no boost.
    function test_Grants_ZeroFloorAppendsNothingKeepsBoost() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.seedBoost(alice, 3);
        uint256 count = host.boxWriteCount();
        uint256 pending = host.pendingMilliEth();
        host.grant(alice, 0.0009 ether, 100, true, 0);
        host.grant(alice, 0.099 ether, 100, true, 100);
        assertEq(host.boxWriteCount(), count, "nothing appended");
        assertEq(host.pendingMilliEth(), pending, "no pending ETH");
        assertEq(host.boostTier(alice), 3, "the boost survives");
    }

    /// @notice Thirty boxes from 11.86 ETH store 30 x 0.395 ETH (11.85 ETH); the boost fraction is
    ///         still taken on the original 11.86 ETH (2.5 ETH capped uplift / 11.86 ETH = 2,107 bps).
    function test_Grants_ThirtyBoxesFrom1186WithBoost() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.seedBoost(alice, 3);
        host.grant(alice, 11.86 ether, 100, true, 30);
        uint256 e = _lastEntry();
        assertEq(BoxOrderLib.boCount(e), 30);
        assertEq(BoxOrderLib.boSizeWei(e), 0.395 ether);
        assertEq(BoxOrderLib.boNominal(e), 11.85 ether, "represented value");
        assertEq(BoxOrderLib.boBoostBps(e), uint256(2.5 ether) * 10_000 / 11.86 ether, "boost on the original amount");
        assertEq(host.boostTier(alice), 0, "boost consumed");
    }

    /// @notice Producer extremes that only recordCoverBox sees: a 61.2 ETH subscription cover and a
    ///         0.24 ETH lazy bound fit; the 2,000 ETH cap is stored exactly.
    function test_Grants_CoverExtremesFit() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.grant(alice, 61.2 ether, 30_000, false, 0);
        assertEq(BoxOrderLib.boUnits(_lastEntry()), 61_200);
        assertEq(BoxOrderLib.boScoreCode(_lastEntry()), 4039);
        host.grant(alice, 0.24 ether, 0, true, 1);
        assertEq(BoxOrderLib.boUnits(_lastEntry()), 240);
        host.grant(alice, 2_000 ether, 0, false, 0);
        assertEq(BoxOrderLib.boUnits(_lastEntry()), 2_000_000);
        host.grant(alice, 400 ether, 0, false, 100);
        assertEq(BoxOrderLib.boUnits(_lastEntry()), 4_000);
        assertEq(BoxOrderLib.boCount(_lastEntry()), 100);
    }

    // =========================================================================
    // Paths outside the queue keep wide amounts
    // =========================================================================

    /// @notice A redemption order never enters the queue: 50,000 ETH resolves as 20 boxes of
    ///         2,500 ETH each, above the queued 2,000 ETH cap, without reverting.
    function test_Redemption_PerBoxAboveQueuedCap() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        uint32 id = _id(alice);
        vm.deal(address(sdgnrs), 60_000 ether);
        vm.recordLogs();
        vm.prank(address(sdgnrs));
        host.redemption{value: 50_000 ether}(alice, id, 50_000 ether, uint256(keccak256("big-redemption")), 9);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 seen;
        uint256 mul = host.evMultiplier(0);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED
                && uint256(logs[i].topics[2]) == ((uint256(1) << 47) | 9)) {
                (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                assertEq(amount, 2_500 ether * mul / 10_000, "a 2,500 ETH box at the snapshotted score");
                ++seen;
            }
        }
        assertGt(seen, 0, "boxes opened");
        assertLe(seen, 20, "at most 20 redemption boxes");
    }

    /// @notice Direct boxes keep their raw amount: a 0.0005 ETH box is not floored to a unit.
    function test_Direct_SubUnitAmountUnfloored() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        uint32 id = _id(alice);
        uint256 mul = host.evMultiplier(0);
        for (uint256 k = 1; k < 40; ++k) {
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            host.direct(alice, id, 0.0005 ether, uint256(keccak256(abi.encode("sub-unit", k))));
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED) {
                    (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                    assertEq(amount, 0.0005 ether * mul / 10_000, "direct box keeps its sub-unit amount");
                    return;
                }
            }
            assertTrue(vm.revertToState(snap));
        }
        revert("no plain direct box in 40 words");
    }

    // =========================================================================
    // Purchase-time value, bounty, foil
    // =========================================================================

    /// @notice Each preset bought at one level keeps its purchase-time value after the price
    ///         changes; the reward and allowance read the opening level.
    function test_Presets_KeepPurchaseValueAcrossPriceChange() public {
        uint256[3] memory mult = [uint256(1), 5, 25];
        for (uint256 k; k < 3; ++k) {
            uint256 snap = vm.snapshotState();
            uint256 price = PriceLookupLib.priceForLevel(host.activeLevel());
            (uint48 b, uint256 p) = _buy(alice, BoxOrderLib.boInput(k, 10, 0));
            uint256 e = host.entryAt(b, p);
            assertEq(BoxOrderLib.boSizeWei(e), mult[k] * price, "stored at the purchase level");
            TicketQueueStorage.retireCompleted(address(game), 99);
            host.setLevel(99); // opening level 100: a 0.24 ETH ticket price
            Vm.Log[] memory logs = _drain(WORD ^ k);
            uint256 mul = host.evMultiplier(BoxOrderLib.boScore(e));
            uint256 seen;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED && uint256(logs[i].topics[2]) == _ref(b, p)) {
                    (uint256 amount,,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                    if (mul <= 10_000) assertEq(amount, mult[k] * price * mul / 10_000, "nominal is the purchase-time value");
                    ++seen;
                }
            }
            assertGt(seen, 0);
            assertTrue(vm.revertToState(snap));
        }
    }

    /// @notice The biggest-box bounty is custom-only and per box: a 6 ETH large preset and ten
    ///         1 ETH customs never arm; one 5 ETH custom arms; 4.999 ETH does not.
    function test_Bounty_CustomOnlyPerBox() public {
        host.setLevel(99);
        assertEq(PriceLookupLib.priceForLevel(host.activeLevel()), 0.24 ether);
        _buy(alice, BoxOrderLib.boLarges(1));
        _buy(alice, BoxOrderLib.boCustoms(10, 1 ether));
        _buy(alice, BoxOrderLib.boCustom(4.999 ether));
        assertEq(coinflip.biggestLuckboxEver(), 0, "no preset, split or sub-floor custom arms");
        _buy(alice, BoxOrderLib.boCustom(5 ether));
        assertEq(coinflip.biggestLuckboxEver(), 5 ether, "one 5 ETH custom arms");
    }

    /// @notice A foil purchase with a box leg of each kind charges exactly the box cost on top of
    ///         the same foil purchase without a box: Foil's quote and Mint's charge agree.
    function test_Foil_QuoteMatchesChargeForEveryKind() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        (,,,, uint256 priceWei) = host.purchaseInfo();
        uint256 value = priceWei * 40;
        uint256 snap = vm.snapshotState();
        uint256 a0 = host.afkingFundingOf(alice);
        vm.prank(alice);
        host.purchase{value: value}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        uint256 baseCredit = host.afkingFundingOf(alice) - a0;
        assertTrue(vm.revertToState(snap));
        uint256[4] memory orders =
            [BoxOrderLib.boSmalls(3), BoxOrderLib.boMeds(2), BoxOrderLib.boLarges(1), BoxOrderLib.boCustoms(4, 0.123 ether)];
        for (uint256 k; k < 4; ++k) {
            snap = vm.snapshotState();
            (, uint256 boxCost) = host.decode(orders[k], host.activeLevel());
            vm.prank(alice);
            host.purchase{value: value + boxCost}(0, 400, orders[k], bytes32(0), MintPaymentKind.DirectEth, true);
            assertEq(host.afkingFundingOf(alice) - a0, baseCredit, "the box leg charged exactly its quote");
            assertEq(BoxOrderLib.boNominal(_lastEntry()), boxCost, "entry represents the charged box cost");
            assertTrue(vm.revertToState(snap));
        }
    }
}

/// @dev Storage writes the producer-bound fixtures need, compiled against the live layout.
contract CompactProducerFixture is DegenerusGameStorage, WalletSeed {
    function setLevel(uint24 lvl) external {
        for (uint24 past = 1; past <= lvl; ++past) {
            _consume(past);
            _consume(past | TICKET_SLOT_BIT);
            _consume(_tqFarFutureKey(past));
        }
        level = lvl;
    }

    function _consume(uint24 key) private {
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        uint256 n = _ticketQueueLength(key);
        for (uint256 i; i < n; ++i) _setEntryOwed(key, _tqPositionAt(q, i), 0);
        _releaseTicketQueue(key);
    }

    function setDeitySales(uint8 sold) external { deityPassSales = sold; }

    function seedWhaleBoon(address who, uint8 tier) external {
        uint32 id = _seedWallet(who);
        uint256 s0 = boonPacked[id].slot0 & BP_WHALE_CLEAR;
        boonPacked[id].slot0 = s0 | (uint256(tier) << BP_WHALE_TIER_SHIFT)
            | (uint256(_simulatedDayIndex()) << BP_WHALE_DAY_SHIFT);
    }
}

/// @title Producer bounds of the 2,000 ETH / 100-box queued limits, through the real purchase paths
contract LootboxCompactProducerBoundsTest is DeployProtocol {
    CompactProducerFixture private fixture;

    function setUp() public {
        _deployProtocol();
        fixture = new CompactProducerFixture();
        vm.warp(block.timestamp + 1 days);
    }

    function _fixtureCall(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), original);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }

    function _lastEntry(address who) private view returns (uint256 e) {
        uint48 wb = RecyclingState.writeBuffer(address(game));
        e = RecyclingState.boxEntry(address(game), wb, RecyclingState.boxCount(address(game), wb) - 1);
        assertEq(BoxOrderLib.boId(e), game.walletIdOf(who), "the buyer's entry");
    }

    /// @notice The thirtieth sellable deity pass costs 300 ETH << 6 = 19,200 ETH; from level 10 its
    ///         box is 10% = 1,920 ETH, inside the 2,000 ETH cap.
    function test_DeityThirtiethSaleBoxFits() public {
        _fixtureCall(abi.encodeCall(CompactProducerFixture.setLevel, (uint24(15))));
        _fixtureCall(abi.encodeCall(CompactProducerFixture.setDeitySales, (uint8(29))));
        address buyer = makeAddr("lastDeity");
        vm.deal(buyer, 19_200 ether);
        vm.prank(buyer);
        game.purchaseDeityPass{value: 19_200 ether}(0, 1, bytes32(0));
        uint256 e = _lastEntry(buyer);
        assertEq(BoxOrderLib.boCount(e), 1);
        assertEq(BoxOrderLib.boUnits(e), 1_920_000, "1,920 ETH stored exactly");
        assertLe(BoxOrderLib.boUnits(e), BoxOrderLib.UNITS_MAX);
    }

    /// @notice 1,000 passes at the 4 ETH standard price: 100 boxes of 4 ETH; with a boon discount
    ///         on the first pass the 10% total still floors per box.
    function test_ThousandWhalePassesStandardPrice() public {
        _fixtureCall(abi.encodeCall(CompactProducerFixture.setLevel, (uint24(4))));
        address buyer = makeAddr("thousand");
        vm.deal(buyer, 4_000 ether);
        uint256 nextBefore = game.nextPrizePoolView();
        uint256 futureBefore = game.futurePrizePoolView();
        vm.prank(buyer);
        game.purchaseWhalePass{value: 4_000 ether}(0, 1000, bytes32(0));
        uint256 e = _lastEntry(buyer);
        assertEq(BoxOrderLib.boCount(e), 100);
        assertEq(BoxOrderLib.boSizeWei(e), 4 ether, "the 4 ETH per-box maximum");
        assertEq(game.nextPrizePoolView() + game.futurePrizePoolView() - nextBefore - futureBefore, 4_000 ether,
            "the full price funds the pools, independent of the represented boxes");

        address boon = makeAddr("boonThousand");
        _fixtureCall(abi.encodeCall(CompactProducerFixture.seedWhaleBoon, (boon, uint8(3))));
        uint256 price = 4 ether * 6500 / 10_000 + 4 ether * 999;
        vm.deal(boon, price);
        vm.prank(boon);
        game.purchaseWhalePass{value: price}(0, 1000, bytes32(0));
        e = _lastEntry(boon);
        assertEq(BoxOrderLib.boCount(e), 100);
        assertEq(BoxOrderLib.boSizeWei(e), (price / 10) / 100 / 0.001 ether * 0.001 ether, "floored per box");
        assertEq(game.afkingFundingOf(boon), 0, "the discounted quote was charged exactly");
    }
}
