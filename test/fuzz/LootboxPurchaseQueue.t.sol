// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {SigFigLib} from "../../contracts/libraries/SigFigLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {QueueHost} from "../helpers/BoxQueueHost.sol";

/// @dev Records the Game's box-cursor slot each time a reward credit reaches Coinflip. Etched over
///      Coinflip, so it keeps its log at a private slot base clear of Coinflip's own storage.
contract CursorProbe {
    address private immutable GAME;
    uint256 private immutable SLOT;
    uint256 private constant BASE = uint256(keccak256("phase-c.cursor-probe"));

    constructor(address game, uint256 slot) {
        GAME = game;
        SLOT = slot;
    }

    function creditFlip(uint32, uint256) external {
        uint256 value = uint256(DegenerusGame(payable(GAME)).extsload(bytes32(SLOT)));
        uint256 base = BASE;
        assembly ("memory-safe") {
            let n := sload(base)
            sstore(add(base, add(n, 1)), value)
            sstore(base, add(n, 1))
        }
    }

    function seenCount() external view returns (uint256 n) {
        uint256 base = BASE;
        assembly ("memory-safe") { n := sload(base) }
    }

    function seen(uint256 i) external view returns (uint256 v) {
        uint256 base = BASE;
        assembly ("memory-safe") { v := sload(add(base, add(i, 1))) }
    }

    fallback() external {
        assembly ("memory-safe") { return(0, 64) }
    }
}

/// @title LootboxPurchaseQueue -- Phase C: one queue entry per purchase (plan C1-C8, C7 table)
contract LootboxPurchaseQueueTest is DeployProtocol {
    QueueHost internal host;
    address internal alice;
    address internal bob;

    bytes32 internal constant OPENED = keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant PRESALE_OPENED =
        keccak256("PresaleBoxOpened(address,uint48,uint256,uint256,uint256,uint256,bool,uint32,uint32)");
    bytes32 internal constant REMAINDER = keccak256("PresaleBoxRemainderSwept(address,uint256)");
    bytes32 internal constant BOX_BUY = keccak256("LootBoxBuy(address,uint48,uint32,uint256)");
    bytes32 internal constant PRESALE_BUY = keccak256("PresaleBoxBuy(address,uint48,uint32,uint256,bool)");

    uint256 internal constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572;
    uint256 internal constant BOX_OPEN_TAG = 0x426f784f70656e;
    uint256 internal constant BOX_BOON_TAG = 0x426f78426f6f6e;
    uint256 internal constant AFKING_BOX_TAG = 0x41666b696e67426f78;
    uint48 internal constant QUEUED_ENTRY_TAG = uint48(1) << 46;
    uint48 internal constant REDEMPTION_INDEX_TAG = uint48(1) << 47;

    uint256 internal constant WORD = 0x5eed000000000000000000000000000000000000000000000000000000c0ffee;
    uint256 internal constant ALLOWANCE = 25_000_000;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(QueueHost).runtimeCode);
        host = QueueHost(payable(address(game)));
        alice = makeAddr("queueAlice");
        bob = makeAddr("queueBob");
        vm.deal(alice, 1e12 ether);
        vm.deal(bob, 1e12 ether);
        vm.deal(address(game), 10_000 ether);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _cost(uint256 boxOrder) internal view returns (uint256 cost) {
        (, cost) = host.decode(boxOrder, host.activeLevel());
    }

    function _buy(address who, uint256 boxOrder) internal returns (uint48 buffer, uint256 position) {
        buffer = host.writeBuffer();
        position = host.boxWriteCount();
        uint256 cost = _cost(boxOrder);
        vm.prank(who);
        host.purchase{value: cost}(who, 0, boxOrder, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(host.boxWriteCount(), position + 1, "one purchase, one entry");
    }

    function _id(address who) internal view returns (uint32) { return host.walletIdOf(who); }

    function _drain(uint256 word) internal returns (Vm.Log[] memory logs) {
        host.sealAndPublish(word);
        vm.recordLogs();
        MineFlipGas.Result memory r = host.work(ALLOWANCE);
        logs = vm.getRecordedLogs();
        assertTrue(r.done, "drain completes");
    }

    function _ref(uint48 buffer, uint256 position) internal pure returns (uint48) {
        return QUEUED_ENTRY_TAG | (uint48(position) << 1) | buffer;
    }

    function _root(uint256 word, uint48 buffer, uint256 position) internal pure returns (uint256) {
        return EntropyLib.hash4(QUEUED_ORDER_DOMAIN, word, buffer, position);
    }

    /// @dev Whether box seed `seed` emits LootBoxOpened (every branch except the spins), and its
    ///      rolled target level. Boxes here are large enough that the pass branch pays a pass.
    function _rollOf(uint256 seed, uint24 currentLevel) internal pure returns (bool emits, uint24 target) {
        uint256 rangeRoll = uint16(seed) % 100;
        target = rangeRoll < 20
            ? currentLevel + uint24(uint16(seed >> 24) % 46 + 5)
            : currentLevel + uint24(uint8(seed >> 16) % 5);
        uint256 path = uint16(seed >> 40) % 20;
        emits = path <= 10 || path == 14 || path == 15 || path == 16;
    }

    /// @dev Expected LootBoxOpened target levels, in order, for `boxes` queued boxes rooted at `rootWord`.
    function _expectedTargets(uint256 rootWord, uint32 id, uint256 boxes, uint24 currentLevel)
        internal
        pure
        returns (uint24[] memory targets, uint256 n)
    {
        targets = new uint24[](boxes);
        for (uint256 i = 1; i <= boxes; ++i) {
            (bool emits, uint24 target) =
                _rollOf(EntropyLib.hash4(rootWord, uint256(id), BOX_OPEN_TAG, i), currentLevel);
            if (emits) targets[n++] = target;
        }
    }

    /// @dev Target levels of the LootBoxOpened logs carrying `tag`, in emission order.
    function _openedTargets(Vm.Log[] memory logs, uint48 tag) internal pure returns (uint24[] memory targets, uint256 n) {
        targets = new uint24[](logs.length);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED && uint256(logs[i].topics[2]) == tag) {
                (, uint24 futureLevel,,,) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                targets[n++] = futureLevel;
            }
        }
    }

    function _assertSeeded(Vm.Log[] memory logs, uint48 tag, uint256 rootWord, uint32 id, uint256 boxes) internal {
        (uint24[] memory expected, uint256 en) = _expectedTargets(rootWord, id, boxes, host.level() + 1);
        (uint24[] memory seen, uint256 sn) = _openedTargets(logs, tag);
        assertGt(en, 0, "fixture rolls at least one non-spin box");
        assertEq(sn, en, "LootBoxOpened count matches the predicted non-spin boxes");
        for (uint256 i; i < en; ++i) assertEq(seen[i], expected[i], "box target level follows its predicted seed");
    }

    function _count(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) ++n;
    }

    // =========================================================================
    // Packing
    // =========================================================================

    /// @notice The entry fields tile bits 0..254 without overlap; bit 255 is never written.
    function test_Packing_FieldsTileWithoutOverlap() public pure {
        uint256[17] memory masks = [
            uint256(0xFFFFFFFF), // id
            uint256(0xFFFFFF) << 32, // level
            uint256(0x7FFF) << 56, // score
            uint256(0x3FFF) << 71, // boost
            uint256(0x3FFF) << 85, // ev
            uint256(1) << 99, // distress
            uint256(0x7F) << 100,
            uint256(0x7F) << 107,
            uint256(0x7F) << 114,
            uint256(0x7F) << 121, // counts
            uint256(0xFFFFFFFFFFFFFF) << 128, // size
            uint256(1) << 184, // cover
            uint256(0x3FFFFFFFFFFFFFFFF) << 185, // presale amount
            uint256(7) << 251, // tier
            uint256(1) << 254, // closing
            0,
            0
        ];
        uint256 union;
        for (uint256 i; i < masks.length; ++i) {
            assertEq(union & masks[i], 0, "fields overlap");
            union |= masks[i];
        }
        assertEq(union, type(uint256).max >> 1, "fields tile bits 0..254");
    }

    /// @notice Input validation: four independent counts, sum 100 accepted and 101 rejected, an
    ///         empty order, an under-minimum custom, a size without customs and any bit >= 88 rejected.
    function test_Packing_InputCodecBounds() public {
        uint24 lvl = host.activeLevel();
        uint256 price = PriceLookupLib.priceForLevel(lvl);
        (uint256 lanes, uint256 cost) = host.decode(BoxOrderLib.boOrder(100, 0, 0, 0, 0), lvl);
        assertEq(BoxOrderLib.boSmall(lanes), 100);
        assertEq(cost, 100 * price);
        (lanes, cost) = host.decode(BoxOrderLib.boOrder(0, 100, 0, 0, 0), lvl);
        assertEq(BoxOrderLib.boMed(lanes), 100);
        assertEq(cost, 500 * price);
        (lanes, cost) = host.decode(BoxOrderLib.boOrder(0, 0, 100, 0, 0), lvl);
        assertEq(BoxOrderLib.boLarge(lanes), 100);
        assertEq(cost, 2500 * price);
        (lanes, cost) = host.decode(BoxOrderLib.boOrder(0, 0, 0, 100, 0.01 ether), lvl);
        assertEq(BoxOrderLib.boCustomCount(lanes), 100);
        assertEq(cost, 1 ether);
        (lanes, cost) = host.decode(BoxOrderLib.boOrder(25, 25, 25, 25, 0.02 ether), lvl);
        assertEq(BoxOrderLib.boSmall(lanes) + BoxOrderLib.boMed(lanes) + BoxOrderLib.boLarge(lanes)
            + BoxOrderLib.boCustomCount(lanes), 100);
        assertEq(BoxOrderLib.boLevel(lanes), lvl);
        assertEq(cost, 25 * 31 * price + 25 * 0.02 ether);

        vm.expectRevert();
        host.decode(BoxOrderLib.boOrder(26, 25, 25, 25, 0.02 ether), lvl);
        vm.expectRevert();
        host.decode(0x80, lvl); // 128 smalls: under the 8-bit lane, over the cap
        vm.expectRevert();
        host.decode(uint256(1) << 24, lvl); // a custom with no size
        vm.expectRevert();
        host.decode(BoxOrderLib.boOrder(0, 0, 0, 1, 0.01 ether - 1 gwei), lvl);
        vm.expectRevert();
        host.decode(1 | (uint256(1) << 32), lvl); // size without customs
        vm.expectRevert();
        host.decode(1 | (uint256(1) << 88), lvl); // a nonzero bit at 88
        vm.expectRevert();
        host.decode(1 | (uint256(1) << 255), lvl);
    }

    /// @notice The maximum encoded size is accepted and stored exactly; one gwei more rejects
    ///         before anything could truncate.
    function test_Amounts_MaximumEncodedSizeStoredExactly() public {
        uint256 maxSize = (uint256(1) << 56) - 1;
        uint256 order = (uint256(1) << 24) | (maxSize << 32);
        (uint48 b, uint256 p) = _buy(alice, order);
        uint256 word = host.entryAt(b, p);
        assertEq(BoxOrderLib.boSizeWei(word), maxSize * 1 gwei);
        assertEq(BoxOrderLib.boCustomCount(word), 1);
        assertEq(word >> 255, 0, "bit 255 zero");

        uint256 over = (uint256(1) << 24) | ((maxSize + 1) << 32);
        vm.prank(alice);
        vm.expectRevert();
        host.purchase{value: (maxSize + 1) * 1 gwei}(alice, 0, over, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @notice An exact-gwei custom is charged exactly, banks exactly in pending ETH, and a 100,000 ETH
    ///         box resolves through every reward branch without reverting.
    function test_Amounts_ExactGweiChargeAndLargeBox() public {
        uint256 size = 0.012345678 ether; // whole gwei
        uint256 order = BoxOrderLib.boCustoms(3, size);
        assertEq(_cost(order), 3 * size);
        uint256 pendingBefore = host.pendingMilliEth();
        uint256 balanceBefore = alice.balance;
        (uint48 b, uint256 p) = _buy(alice, order);
        assertEq(balanceBefore - alice.balance, 3 * size, "charged exactly count x size");
        assertEq(BoxOrderLib.boSizeWei(host.entryAt(b, p)), size);
        assertEq(host.pendingMilliEth(), pendingBefore + 3 * size / 1e15);

        (b, p) = _buy(bob, BoxOrderLib.boCustom(100_000 ether));
        assertEq(BoxOrderLib.boSizeWei(host.entryAt(b, p)), 100_000 ether);
        _drain(WORD);
        (uint256 count, uint256 cursor, bool complete) = host.readState();
        assertEq(count, 2);
        assertEq(cursor, 2);
        assertTrue(complete);
    }

    // =========================================================================
    // Appends
    // =========================================================================

    /// @notice Two purchases by one wallet are two entries at consecutive positions; different sizes
    ///         and levels; the first entry is byte-for-byte unchanged by the second; LootBoxBuy
    ///         carries each position.
    function test_Appends_SameWalletTwiceIsTwoEntries() public {
        vm.recordLogs();
        (uint48 b0, uint256 p0) = _buy(alice, BoxOrderLib.boCustoms(2, 0.05 ether));
        uint256 first = host.entryAt(b0, p0);
        (uint48 b1, uint256 p1) = _buy(alice, BoxOrderLib.boOrder(3, 1, 0, 1, 0.07 ether));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(b0, b1);
        assertEq(p1, p0 + 1);
        assertEq(host.entryAt(b0, p0), first, "earlier entry untouched");
        uint256 second = host.entryAt(b1, p1);
        assertEq(BoxOrderLib.boId(first), _id(alice));
        assertEq(BoxOrderLib.boId(second), _id(alice));
        assertEq(BoxOrderLib.boSizeWei(first), 0.05 ether);
        assertEq(BoxOrderLib.boSizeWei(second), 0.07 ether);
        assertEq(BoxOrderLib.boCustomCount(first), 2);
        assertEq(BoxOrderLib.boSmall(second), 3);
        assertEq(BoxOrderLib.boMed(second), 1);
        uint256 seenBuys;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != BOX_BUY) continue;
            (uint32 position,) = abi.decode(logs[i].data, (uint32, uint256));
            assertEq(position, seenBuys == 0 ? p0 : p1);
            assertEq(uint256(logs[i].topics[2]), b0);
            ++seenBuys;
        }
        assertEq(seenBuys, 2);
    }

    /// @notice A sealed buffer takes no new entry: later purchases append to the other buffer from
    ///         position 0, and the sealed entries and read count are unchanged. After the drained
    ///         buffer is sealed again, its positions are reused from 0 and old words are overwritten.
    function test_Appends_SealedBufferUntouchedAndReuse() public {
        (uint48 b0,) = _buy(alice, BoxOrderLib.boSmalls(1));
        _buy(bob, BoxOrderLib.boSmalls(2));
        uint256 sealedFirst = host.entryAt(b0, 0);
        host.sealAndPublish(WORD);
        (uint256 readCount,,) = host.readState();
        assertEq(readCount, 2);
        assertEq(host.boxWriteCount(), 0);
        (uint48 b1, uint256 p1) = _buy(bob, BoxOrderLib.boSmalls(3));
        assertTrue(b1 != b0);
        assertEq(p1, 0);
        assertEq(host.entryAt(b0, 0), sealedFirst);
        (readCount,,) = host.readState();
        assertEq(readCount, 2);
        assertTrue(host.work(ALLOWANCE).done);

        host.sealAndPublish(WORD ^ 1);
        assertTrue(host.work(ALLOWANCE).done);
        assertEq(host.writeBuffer(), b0, "the first buffer takes appends again");
        (uint48 b2, uint256 p2) = _buy(alice, BoxOrderLib.boCustom(0.03 ether));
        assertEq(b2, b0);
        assertEq(p2, 0, "positions restart");
        assertEq(BoxOrderLib.boSizeWei(host.entryAt(b0, 0)), 0.03 ether, "stale word overwritten");
    }

    // =========================================================================
    // Modifiers
    // =========================================================================

    /// @notice Each entry carries its own post-action score.
    function test_Modifiers_ScorePerPurchase() public {
        (uint48 b, uint256 p) = _buy(alice, BoxOrderLib.boSmalls(1));
        (uint256 score1,) = host.playerActivityScore(alice);
        assertEq(BoxOrderLib.boScore(host.entryAt(b, p)), score1);
        (b, p) = _buy(alice, BoxOrderLib.boOrder(0, 0, 4, 0, 0));
        (uint256 score2,) = host.playerActivityScore(alice);
        assertEq(BoxOrderLib.boScore(host.entryAt(b, p)), score2);
    }

    /// @notice A live boost is consumed by the first purchase only; distress is snapshotted per
    ///         purchase and routes that purchase's spend wholly to next.
    function test_Modifiers_BoostOnceAndDistressToggle() public {
        _buy(alice, BoxOrderLib.boSmalls(1)); // registers alice
        host.seedBoost(alice, 3); // 25%
        (uint48 b, uint256 p) = _buy(alice, BoxOrderLib.boCustom(1 ether));
        assertEq(BoxOrderLib.boBoostBps(host.entryAt(b, p)), 2500);
        assertEq(host.boostTier(alice), 0, "boon consumed");
        (b, p) = _buy(alice, BoxOrderLib.boCustom(1 ether));
        assertEq(BoxOrderLib.boBoostBps(host.entryAt(b, p)), 0);
        assertFalse(BoxOrderLib.boDistress(host.entryAt(b, p)));

        vm.warp(block.timestamp + 260 days);
        host.seedDistress(true);
        assertTrue(host.distress());
        (b, p) = _buy(alice, BoxOrderLib.boCustom(1 ether));
        assertTrue(BoxOrderLib.boDistress(host.entryAt(b, p)));
        host.seedDistress(false);
        assertFalse(host.distress());
        (b, p) = _buy(alice, BoxOrderLib.boCustom(1 ether));
        assertFalse(BoxOrderLib.boDistress(host.entryAt(b, p)));
    }

    /// @notice The shared per-(wallet, level) EV allowance spans entries: full, partial, exhausted.
    function test_Modifiers_SharedEvAllowanceAcrossEntries() public {
        _buy(alice, BoxOrderLib.boSmalls(1)); // registers alice
        uint32 id = _id(alice);
        uint24 key = host.level() + 1;
        uint256 left = 10 ether - host.evUsed(id, key);
        assertGt(left, 4 ether, "fixture leaves room for one full and one partial draw");
        uint48 b = host.writeBuffer();
        uint256 p = host.boxWriteCount();
        for (uint256 i; i < 3; ++i) {
            host.grant(alice, 6 ether, 30_000, false, 0);
            uint256 drawn = left < 6 ether ? left : 6 ether;
            left -= drawn;
            assertEq(BoxOrderLib.boEvBps(host.entryAt(b, p + i)), drawn * 10_000 / 6 ether, "entry's own fraction");
        }
        assertEq(left, 0);
        assertEq(host.evUsed(id, key), 10 ether, "the shared allowance is exhausted across entries");
    }

    // =========================================================================
    // Presale
    // =========================================================================

    function _presale(address who, uint256 amount) internal returns (uint48 buffer, uint256 position) {
        buffer = host.writeBuffer();
        position = host.boxWriteCount();
        vm.prank(who);
        host.buyPresaleBox{value: amount}(who, amount);
    }

    /// @notice The DGNRS tier freezes from the purchase's starting sold amount at every boundary.
    function test_Presale_TierBoundaries() public {
        uint256[10] memory sold = [uint256(0), 9.99 ether, 10 ether, 19.99 ether, 20 ether, 29.99 ether,
            30 ether, 39.99 ether, 40 ether, 49.99 ether];
        uint256[10] memory tier = [uint256(0), 0, 1, 1, 2, 2, 3, 3, 4, 4];
        for (uint256 i; i < sold.length; ++i) assertEq(host.tierOf(sold[i]), tier[i]);
        _buy(alice, BoxOrderLib.boSmalls(1)); // registers alice
        // A purchase straddling a boundary keeps its starting tier.
        host.seedPresale(9.995 ether, alice, 1 ether);
        (uint48 b2, uint256 p2) = _presale(alice, 0.5 ether);
        assertEq(BoxOrderLib.boPresaleTier(host.entryAt(b2, p2)), 0);
        assertEq(BoxOrderLib.boPresaleWei(host.entryAt(b2, p2)), 0.5 ether);
        for (uint256 i; i < sold.length; ++i) {
            host.seedPresale(uint96(sold[i]), alice, 1 ether);
            (uint48 b, uint256 p) = _presale(alice, 0.01 ether);
            uint256 word = host.entryAt(b, p);
            assertEq(BoxOrderLib.boPresaleTier(word), tier[i], "tier frozen at purchase");
            assertEq(BoxOrderLib.boPresaleWei(word), 0.01 ether);
            assertEq(BoxOrderLib.boCount(word), 0, "presale-only entry");
        }
    }

    /// @notice One wallet's repeat presale purchases are independent entries; a credit shortfall
    ///         reverts the whole purchase, appending nothing.
    function test_Presale_RepeatPurchasesAndShortfallRollback() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.seedPresale(0, alice, 0.05 ether);
        (uint48 b, uint256 p) = _presale(alice, 0.02 ether);
        (, uint256 q) = _presale(alice, 0.02 ether);
        assertEq(q, p + 1);
        assertEq(BoxOrderLib.boPresaleWei(host.entryAt(b, p)), 0.02 ether);
        assertEq(BoxOrderLib.boPresaleWei(host.entryAt(b, q)), 0.02 ether);
        uint256 count = host.boxWriteCount();
        vm.prank(alice);
        vm.expectRevert();
        host.buyPresaleBox{value: 0.02 ether}(alice, 0.02 ether); // 0.01 credit left
        assertEq(host.boxWriteCount(), count, "nothing appended");
        assertEq(host.presaleCredit(_id(alice)), 0.01 ether);
    }

    /// @notice A same-call ordinary + presale purchase is one entry carrying both legs.
    function test_Presale_SameCallSharesOneEntry() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.seedPresale(0, alice, 1 ether);
        uint48 b = host.writeBuffer();
        uint256 p = host.boxWriteCount();
        uint256 order = BoxOrderLib.boCustoms(2, 0.04 ether);
        uint256 cost = _cost(order);
        vm.recordLogs();
        vm.prank(alice);
        host.buyLootboxAndPresaleBox{value: cost + 0.03 ether}(
            alice, 0, order, bytes32(0), MintPaymentKind.DirectEth, 0.03 ether
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(host.boxWriteCount(), p + 1, "one entry");
        uint256 word = host.entryAt(b, p);
        assertEq(BoxOrderLib.boCustomCount(word), 2);
        assertEq(BoxOrderLib.boPresaleWei(word), 0.03 ether);
        assertEq(_count(logs, BOX_BUY), 1);
        assertEq(_count(logs, PRESALE_BUY), 1);
    }

    /// @notice The requested amount clamps to the cap; the exact applied amount is stored, down to
    ///         1 wei. The closing entry's own resolution pays the remainder, after every earlier
    ///         presale box has settled, and no other entry sweeps.
    function test_Presale_OneWeiCloseAndRemainderAfterEarlierBoxes() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        _buy(bob, BoxOrderLib.boSmalls(1));
        host.seedPresale(40 ether, alice, 1 ether);
        (, uint256 pa) = _presale(alice, 0.5 ether);
        host.seedPresale(50 ether - 1, bob, 1 ether);
        uint256 balanceBefore = bob.balance;
        (uint48 b, uint256 pb) = _presale(bob, 0.01 ether);
        assertEq(balanceBefore - bob.balance, 0.01 ether, "the payer sent the request");
        uint256 closing = host.entryAt(b, pb);
        assertEq(BoxOrderLib.boPresaleWei(closing), 1, "exact 1-wei applied amount");
        assertTrue(BoxOrderLib.boPresaleClosing(closing));
        assertTrue(host.presaleBoxEthRemaining() == 0);

        Vm.Log[] memory logs = _drain(WORD);
        uint256 openedA = type(uint256).max;
        uint256 openedB = type(uint256).max;
        uint256 swept = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == PRESALE_OPENED) {
                if (uint256(logs[i].topics[2]) == _ref(b, pa)) openedA = i;
                if (uint256(logs[i].topics[2]) == _ref(b, pb)) openedB = i;
            }
            if (logs[i].topics[0] == REMAINDER) {
                assertEq(swept, type(uint256).max, "one sweep");
                swept = i;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), bob, "to the closing wallet");
            }
        }
        assertLt(openedA, openedB);
        assertLt(openedB, swept, "remainder follows the closing box's own roll");
        assertEq(IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.PresaleBox), 0, "pool drained to the closer");
    }

    // =========================================================================
    // Grants
    // =========================================================================

    /// @notice A cover after a full manual order is its own one-box entry; repeated covers are
    ///         repeated entries; a 100-pass bundle is 100 equal customs; a grant under one gwei per
    ///         box appends nothing and does not revert.
    function test_Grants_CoversAndPassBundles() public {
        (uint48 b, uint256 p) = _buy(alice, BoxOrderLib.boSmalls(100));
        uint256 manual = host.entryAt(b, p);
        host.grant(alice, 0.3 ether + 7, 100, false, 0);
        host.grant(alice, 0.2 ether, 100, false, 0);
        uint256 c1 = host.entryAt(b, p + 1);
        uint256 c2 = host.entryAt(b, p + 2);
        assertEq(host.entryAt(b, p), manual, "manual entry untouched");
        assertTrue(BoxOrderLib.boCover(c1) && BoxOrderLib.boCover(c2));
        assertEq(BoxOrderLib.boCount(c1), 1);
        assertEq(BoxOrderLib.boSizeWei(c1), 0.3 ether, "gwei floor; the 7 wei stay accounting-side");
        assertEq(BoxOrderLib.boSizeWei(c2), 0.2 ether);

        _buy(bob, BoxOrderLib.boSmalls(1)); // registered, as every pass buyer is
        host.grant(bob, 100 * 0.04 ether + 99, 100, true, 100);
        uint256 bundle = host.entryAt(b, p + 4);
        assertEq(BoxOrderLib.boId(bundle), _id(bob));
        assertEq(BoxOrderLib.boCustomCount(bundle), 100);
        assertEq(BoxOrderLib.boCount(bundle), 100);
        assertEq(BoxOrderLib.boSizeWei(bundle), 0.04 ether);

        uint256 count = host.boxWriteCount();
        host.grant(alice, 99 gwei, 100, true, 100);
        assertEq(host.boxWriteCount(), count, "sub-gwei-per-box grant appends nothing");
        assertTrue(host.work(ALLOWANCE).progressed == false, "nothing sealed yet");
        _drain(WORD);
        (uint256 readCount, uint256 cursor, bool complete) = host.readState();
        assertEq(readCount, count);
        assertEq(cursor, count);
        assertTrue(complete);
    }

    // =========================================================================
    // Seeds
    // =========================================================================

    /// @notice Queued box seeds are hash4(root, walletId, BOX_OPEN_TAG, n) with root =
    ///         hash4(domain, word, buffer, position): two entries by one wallet in one cohort roll
    ///         from different roots, and every emitted box matches its predicted seed.
    function test_Seeds_QueuedRootsAtTwoPositions() public {
        (uint48 b, uint256 p0) = _buy(alice, BoxOrderLib.boCustoms(12, 1 ether));
        (, uint256 p1) = _buy(alice, BoxOrderLib.boCustoms(12, 1 ether));
        Vm.Log[] memory logs = _drain(WORD);
        uint32 id = _id(alice);
        _assertSeeded(logs, _ref(b, p0), _root(WORD, b, p0), id, 12);
        _assertSeeded(logs, _ref(b, p1), _root(WORD, b, p1), id, 12);
        assertTrue(_root(WORD, b, p0) != _root(WORD, b, p1));
    }

    /// @notice The same physical position in a later cohort rolls from that cohort's word.
    function test_Seeds_RepeatedPhysicalIndexLaterCohort() public {
        (uint48 b,) = _buy(alice, BoxOrderLib.boCustoms(10, 1 ether));
        _drain(WORD);
        host.sealAndPublish(WORD + 7); // the other buffer, empty
        assertTrue(host.work(ALLOWANCE).done);
        (uint48 b2, uint256 p2) = _buy(alice, BoxOrderLib.boCustoms(10, 1 ether));
        assertEq(b2, b);
        assertEq(p2, 0);
        uint256 later = WORD + 99;
        Vm.Log[] memory logs = _drain(later);
        _assertSeeded(logs, _ref(b, 0), _root(later, b, 0), _id(alice), 10);
    }

    /// @notice Wallet IDs 1 and uint32.max are the owner input as plain uint256 words.
    function test_Seeds_WalletIdBounds() public {
        address hi = makeAddr("maxIdWallet");
        vm.deal(hi, 100 ether);
        host.seedWalletAt(hi, type(uint32).max);
        (uint48 b, uint256 p) = _buy(hi, BoxOrderLib.boCustoms(10, 1 ether));
        assertEq(BoxOrderLib.boId(host.entryAt(b, p)), type(uint32).max);
        address one = host.walletOf(1);
        vm.deal(one, 100 ether);
        (, uint256 p1) = _buy(one, BoxOrderLib.boCustoms(10, 1 ether));
        assertEq(BoxOrderLib.boId(host.entryAt(b, p1)), 1);
        Vm.Log[] memory logs = _drain(WORD);
        _assertSeeded(logs, _ref(b, p), _root(WORD, b, p), type(uint32).max, 10);
        _assertSeeded(logs, _ref(b, p1), _root(WORD, b, p1), 1, 10);
    }

    /// @notice Seeds read the stored wallet ID, never the address: repointing the ID's table entry
    ///         after the append leaves every roll unchanged while the payouts follow the table.
    function test_Seeds_NoAddressInput() public {
        (uint48 b, uint256 p) = _buy(alice, BoxOrderLib.boCustoms(10, 1 ether));
        uint32 id = _id(alice);
        host.repointWallet(id, bob);
        Vm.Log[] memory logs = _drain(WORD);
        _assertSeeded(logs, _ref(b, p), _root(WORD, b, p), id, 10);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == OPENED && uint256(logs[i].topics[2]) == _ref(b, p)) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), bob, "account key decoded once for payouts");
            }
        }
    }

    /// @notice A gas-limited drain, resumed, rolls exactly what a single drain rolls.
    function test_Seeds_PauseResumeInvariance() public {
        for (uint256 i; i < 4; ++i) _buy(i % 2 == 0 ? alice : bob, BoxOrderLib.boCustoms(6, 1 ether));
        host.sealAndPublish(WORD);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        assertTrue(host.work(ALLOWANCE).done);
        bytes32 whole = keccak256(abi.encode(_openedDigest(vm.getRecordedLogs())));
        vm.revertToState(snap);

        uint256 step = GasBounds.HUMAN_ENTRY_GAS + 6 * GasBounds.HUMAN_BOX_GAS + GasBounds.HUMAN_TAIL_GAS
            + MineFlipGas.CHECK_RESERVE + 50_000;
        vm.recordLogs();
        uint256 calls;
        bool done;
        while (!done) {
            done = host.work(step).done;
            ++calls;
            (, uint256 cursor,) = host.readState();
            assertLe(cursor, calls, "at most one entry per bounded call");
        }
        assertGt(calls, 2, "the drain really paused");
        assertEq(keccak256(abi.encode(_openedDigest(vm.getRecordedLogs()))), whole);
    }

    function _openedDigest(Vm.Log[] memory logs) internal pure returns (bytes32 digest) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && (logs[i].topics[0] == OPENED || logs[i].topics[0] == PRESALE_OPENED)) {
                digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
            }
        }
    }

    /// @notice The single-box resolvers mix the wallet ID with their existing commitments: direct
    ///         hash2(word, id); AFKing hash4(word, id, AFKING_BOX_TAG, day); the redemption order
    ///         hash4(word, id, BOX_OPEN_TAG, n) under its tagged batch.
    function test_Seeds_SingleBoxResolversUseWalletId() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        uint32 id = _id(alice);
        uint24 cur = host.level() + 1;

        // Direct: find a word whose box is not a spin, then check its target level.
        uint256 w = _nonSpinWord(id, cur, 0);
        vm.recordLogs();
        host.direct(alice, id, 1 ether, w);
        (uint24[] memory seen, uint256 n) = _openedTargets(vm.getRecordedLogs(), 0);
        (, uint24 target) = _rollOf(EntropyLib.hash2(w, uint256(id)), cur);
        assertEq(n, 1);
        assertEq(seen[0], target, "direct seed = hash2(word, walletId)");

        // AFKing stamped box.
        uint24 day = 7;
        uint256 aw;
        for (uint256 k = 1; ; ++k) {
            aw = uint256(keccak256(abi.encode("afk", k)));
            (bool emits,) = _rollOf(EntropyLib.hash4(aw, uint256(id), AFKING_BOX_TAG, day), cur);
            if (emits) break;
        }
        vm.recordLogs();
        host.afkingBox(alice, id, 1 ether, day, aw);
        (seen, n) = _openedTargets(vm.getRecordedLogs(), 0);
        (, target) = _rollOf(EntropyLib.hash4(aw, uint256(id), AFKING_BOX_TAG, day), cur);
        assertEq(n, 1);
        assertEq(seen[0], target, "AFKing seed = hash4(word, walletId, AFKING_BOX_TAG, day)");

        // Redemption order: three ~1 ETH customs off the ID-mixed redemption word.
        uint256 rw = uint256(keccak256("redemption-word"));
        uint32 batch = 5;
        vm.deal(address(sdgnrs), 10 ether);
        vm.recordLogs();
        vm.prank(address(sdgnrs));
        host.redemption{value: 3 ether}(alice, id, 3 ether, rw, batch);
        _assertSeeded(vm.getRecordedLogs(), REDEMPTION_INDEX_TAG | uint48(batch), rw, id, 3);
    }

    function _nonSpinWord(uint32 id, uint24 cur, uint256 salt) internal pure returns (uint256 w) {
        for (uint256 k = 1; ; ++k) {
            w = uint256(keccak256(abi.encode("direct", salt, k)));
            uint256 seed = EntropyLib.hash2(w, uint256(id));
            uint256 path = uint16(seed >> 40) % 20;
            // Direct boxes never ETH-spin: their roll 19 pays tickets.
            if (path <= 10 || path == 14 || path == 15 || path == 16 || path == 19) return w;
        }
    }

    // =========================================================================
    // Lifecycle
    // =========================================================================

    /// @notice Nothing opens before publication; publication opens everything.
    function test_Lifecycle_NoOpeningBeforePublication() public {
        _buy(alice, BoxOrderLib.boSmalls(2));
        host.sealUnpublished();
        MineFlipGas.Result memory r = host.work(ALLOWANCE);
        assertFalse(r.progressed);
        (, uint256 cursor,) = host.readState();
        assertEq(cursor, 0);
        host.publish(WORD);
        assertTrue(host.work(ALLOWANCE).done);
        (, cursor,) = host.readState();
        assertEq(cursor, 1);
    }

    /// @notice The cursor is stored before an entry's rewards run: the reward credit observes it
    ///         already advanced past the entry being settled.
    function test_Lifecycle_CursorStoredBeforeRewards() public {
        for (uint256 i; i < 3; ++i) _buy(alice, BoxOrderLib.boSmalls(30));
        host.sealAndPublish(WORD);
        CursorProbe probe = new CursorProbe(address(game), GameSlotsBoxCursor.SLOT);
        vm.etch(ContractAddresses.COINFLIP, address(probe).code);
        // The probe's immutables travel with its code; storage starts empty at the Coinflip address.
        assertTrue(host.work(ALLOWANCE).done);
        CursorProbe at = CursorProbe(payable(ContractAddresses.COINFLIP));
        uint256 n = at.seenCount();
        assertGt(n, 0, "at least one entry credited FLIP");
        uint256 last;
        for (uint256 i; i < n; ++i) {
            uint256 cursor = (at.seen(i) >> (GameSlotsBoxCursor.OFFSET * 8)) & type(uint48).max;
            assertGt(cursor, 0, "cursor advanced before the credit");
            assertGe(cursor, last);
            last = cursor;
        }
    }

    /// @notice A failing presale leg reverts its entry's ordinary leg and the cursor move with it.
    function test_Lifecycle_AtomicMixedLegRevert() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        host.seedPresale(50 ether - 0.01 ether, alice, 1 ether);
        uint256 order = BoxOrderLib.boSmalls(3);
        uint256 cost = _cost(order);
        vm.prank(alice);
        host.buyLootboxAndPresaleBox{value: cost + 0.01 ether}(
            alice, 0, order, bytes32(0), MintPaymentKind.DirectEth, 0.01 ether
        );
        host.sealAndPublish(WORD);
        vm.mockCallRevert(
            address(sdgnrs), abi.encodeWithSelector(IsDGNRS.poolBalance.selector, IsDGNRS.Pool.PresaleBox), "boom"
        );
        vm.expectRevert();
        host.work(ALLOWANCE);
        (, uint256 cursor, bool complete) = host.readState();
        assertEq(cursor, 0, "cursor move rolled back");
        assertFalse(complete);
        vm.clearMockedCalls();
        assertTrue(host.work(ALLOWANCE).done);
    }

    /// @notice Settlement is at-most-once; an empty cohort completes at once; a drained cohort whose
    ///         completion was deferred completes without replaying its last entry.
    function test_Lifecycle_AtMostOnceEmptyAndDeferredCompletion() public {
        _buy(alice, BoxOrderLib.boSmalls(2));
        _drain(WORD);
        vm.recordLogs();
        MineFlipGas.Result memory again = host.work(ALLOWANCE);
        assertTrue(again.done);
        assertFalse(again.progressed);
        assertEq(_count(vm.getRecordedLogs(), OPENED), 0, "no replay");

        host.sealAndPublish(WORD + 1); // nothing was bought into this buffer
        (uint256 count,, bool complete) = host.readState();
        assertEq(count, 0);
        assertFalse(complete);
        assertTrue(host.work(ALLOWANCE).done, "empty cohort completes");

        _buy(alice, BoxOrderLib.boSmalls(2));
        host.sealAndPublish(WORD + 2);
        host.setCursorToEnd(); // every entry settled, completion still owed
        vm.recordLogs();
        MineFlipGas.Result memory tail = host.work(ALLOWANCE);
        assertTrue(tail.done);
        assertEq(_count(vm.getRecordedLogs(), OPENED), 0, "completion only, no replay");
        (,, complete) = host.readState();
        assertTrue(complete);
    }

    /// @notice The terminal bit stops unfinished box consumers, as before.
    function test_Lifecycle_TerminalStopsBoxWork() public {
        _buy(alice, BoxOrderLib.boSmalls(2));
        host.sealAndPublish(WORD);
        host.setTerminal();
        MineFlipGas.Result memory r = host.work(ALLOWANCE);
        assertFalse(r.progressed);
        (, uint256 cursor, bool complete) = host.readState();
        assertEq(cursor, 0);
        assertFalse(complete);
    }

    // =========================================================================
    // C8 counters
    // =========================================================================

    /// @notice Box and bet write counts ride lootboxRngPacked; the seal latches both into the read
    ///         lengths and zeroes them; bet ids and the bet view follow the counts.
    function test_Counters_LatchAtSealAndBetView() public {
        _buy(alice, BoxOrderLib.boSmalls(1));
        _buy(bob, BoxOrderLib.boSmalls(1));
        uint48 w = host.writeBuffer();
        vm.prank(alice);
        host.placeDegeneretteBet{value: 0.01 ether}(alice, 0, 0.01 ether, 1, 1);
        vm.prank(bob);
        host.placeDegeneretteBet{value: 0.01 ether}(bob, 0, 0.01 ether, 1, 2);
        assertEq(host.boxWriteCount(), 2);
        assertEq(host.betWriteCount(), 2);
        assertTrue(host.degeneretteBetInfo(w, 2) != 0);
        assertEq(host.degeneretteBetInfo(w, 3), 0);
        host.sealAndPublish(WORD);
        assertEq(host.boxWriteCount(), 0);
        assertEq(host.betWriteCount(), 0);
        assertEq(host.pendingMilliEth(), 0, "pending ETH cleared in the same write");
        (uint256 boxes,,) = host.readState();
        (uint256 bets, uint256 betCursor) = host.betReadState();
        assertEq(boxes, 2);
        assertEq(bets, 2);
        assertEq(betCursor, 0);
        assertTrue(host.degeneretteBetInfo(w, 2) != 0, "read-side bound is the latched count");
        assertEq(host.degeneretteBetInfo(w, 3), 0);
        assertEq(host.degeneretteBetInfo(w ^ 1, 1), 0, "new write buffer is empty");
    }

    /// @notice A foil buy writes its count into the foil cursor slot it already loaded.
    function test_Counters_FoilWriteCount() public {
        uint256 slot = uint256(vm.load(address(game), bytes32(GameSlotsFoil.SLOT)));
        uint256 before = (slot >> (GameSlotsFoil.WRITE_OFFSET * 8)) & type(uint32).max;
        (,,,, uint256 priceWei) = host.purchaseInfo();
        vm.prank(alice);
        host.purchase{value: priceWei * 20}(alice, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        slot = uint256(vm.load(address(game), bytes32(GameSlotsFoil.SLOT)));
        assertEq((slot >> (GameSlotsFoil.WRITE_OFFSET * 8)) & type(uint32).max, before + 1);
    }
}

library GameSlotsBoxCursor {
    uint256 internal constant SLOT = GameSlots.BOX_CURSOR;
    uint256 internal constant OFFSET = GameSlots.BOX_CURSOR_OFFSET;
}

library GameSlotsFoil {
    uint256 internal constant SLOT = GameSlots.FOIL_WRITE_COUNT;
    uint256 internal constant WRITE_OFFSET = GameSlots.FOIL_WRITE_COUNT_OFFSET;
}
