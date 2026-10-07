// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusAffiliate} from "../../contracts/interfaces/IDegenerusAffiliate.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {ICoinflip} from "../../contracts/interfaces/ICoinflip.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PackedTicketSampleLib} from "../../contracts/libraries/PackedTicketSampleLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @dev The production Game plus test doors (module delegatecall, storage seeders and lane reads).
///      Every production function is unchanged.
contract ViewsGameExt is DegenerusGame {
    function x_delegate(address module, bytes calldata data) external payable returns (bytes memory r) {
        bool ok;
        (ok, r) = module.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(r, 32), mload(r)) }
    }

    function x_seedWallet(address a) external returns (uint32 id) {
        (id, ) = _registerWallet(a, type(uint256).max);
    }

    function x_bucketAppend(uint24 lvl, uint8 trait, uint32 id, uint256 n) external {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), trait, id, n, lvl);
    }

    function x_bucketIdAt(uint24 lvl, uint8 trait, uint256 k) external view returns (uint32) {
        return _bucketIdAtUnchecked(lvl, trait, k);
    }

    function x_bucketLength(uint24 lvl, uint8 trait) external view returns (uint256) {
        return _bucketLengthUnchecked(lvl, trait);
    }

    function x_setTicketBufferLevel(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function x_ffKey(uint24 lvl) external pure returns (uint24) { return _tqFarFutureKey(lvl); }
    function x_tqAppend(uint24 key, uint32 id) external { _tqAppend(key, id); }
    function x_tqLen(uint24 key) external view returns (uint256) { return _ticketQueueLength(key); }

    /// @dev Empty `key`'s physical queue (header and tag), so a test owns every lane in it.
    function x_tqReset(uint24 key) external {
        uint24 physical = _ticketQueueStorageKey(key);
        assembly ("memory-safe") {
            mstore(0, physical)
            mstore(32, ticketQueue.slot)
            sstore(keccak256(0, 64), 0)
        }
    }

    function x_tqLaneAt(uint24 key, uint256 k) external view returns (uint32) {
        return _tqPositionAt(ticketQueue[_ticketQueueStorageKey(key)], k);
    }

    function x_setSub(uint32 id, uint8 qty, uint24 startDay, uint24 covered, uint16 latch, uint32 setPos) external {
        Sub storage s = _subOf[id];
        s.dailyQuantity = qty;
        s.afkingStartDay = startDay;
        s.afkCoveredThroughDay = covered;
        s.subStreakLatch = latch;
        s.setPosition = setPos;
    }

    function x_streakBase(uint32 id) external view returns (uint16) { return _streakBaseOf(_subOf[id]); }
    function x_today() external view returns (uint24) { return _simulatedDayIndex(); }
}

/// @dev Stand-in for the jackpot battle at the CRAPS address: answers the four calls the
///      JackpotDraw chunk makes and records the field it is handed. State sits under a hashed
///      root so it cannot collide with the table's own storage.
contract JackpotBattleStub {
    struct State {
        uint256 remaining;
        uint256 cursor;
        uint256 appends;
        uint256[] field;
        mapping(bytes32 => bytes32) saved;
    }

    function _s() private pure returns (State storage s) {
        bytes32 root = keccak256("game-wallet-id-views.battle-stub");
        assembly { s.slot := root }
    }

    function setRemaining(uint256 n) external { _s().remaining = n; }
    function setSaved(bytes32 slot, bytes32 value) external { _s().saved[slot] = value; }
    function fieldOf() external view returns (uint256[] memory) { return _s().field; }
    function appends() external view returns (uint256) { return _s().appends; }

    function jackpotProgress() external pure returns (uint64, uint256, bool, bool) {
        return (1, 0, false, false);
    }

    function prepareJackpotBattle(uint24, uint256 word) external view returns (uint256, uint256, uint256) {
        State storage s = _s();
        return (word, s.cursor, s.remaining);
    }

    function appendJackpotBattle(uint256[] calldata field, uint256 cursor, bool) external {
        State storage s = _s();
        for (uint256 i; i < field.length; ++i) s.field.push(field[i]);
        s.cursor = cursor;
        s.remaining -= field.length;
        ++s.appends;
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory out) {
        out = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) out[i] = _s().saved[slots[i]];
    }
}

/// @title GameWalletIdViews -- Game views, callbacks and doors that carry wallet IDs
/// @notice Samplers return the queue/bucket lane IDs; the jackpot battle field is built from IDs
///         with no wallet-table decode; `payRecordSdgnrs` always names the payee; `creditMiddayRng`
///         returns the donor's ID; `playerActivityScoreCached` returns the ID it read; the afking
///         callbacks key by ID; the Degenerette referrer, gift funder and self bettor are paid and
///         registered by ID; the deity chain pays its hops' payees; `registerWallet` refuses
///         JACKPOT_BATTLE; the Lens mirrors Game's activity score by ID.
contract GameWalletIdViews is DeployProtocol {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 private constant ENTRIES_QUEUED_RANGE = keccak256("EntriesQueuedRange(uint32,uint24,uint24,uint24,uint32)");
    uint8 private constant ETH = 0;
    uint8 private constant FLIP = 1;
    uint8 private constant SYMBOL = 9;
    uint48 private constant IDX = 1;
    uint256 private constant PAID_ADMISSION_WALLETS = 3_000_000_000;

    ViewsGameExt private ext;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(game), address(new ViewsGameExt()).code);
        ext = ViewsGameExt(payable(address(game)));
        vm.deal(address(game), 1_000 ether);
        RecyclingState.seedWriteBuffer(address(game), IDX);
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        vm.store(
            address(game),
            bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((pools & type(uint128).max) | (uint256(1_000_000 ether) << 128))
        );
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _wallet(string memory name) private returns (address a, uint32 id) {
        a = makeAddr(name);
        id = ext.x_seedWallet(a);
    }

    function _walletsLength() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _registrations(Vm.Log[] memory logs, address who) private view returns (uint256 n, uint32 id) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED
                && address(uint160(uint256(logs[i].topics[2]))) == who) {
                ++n;
                id = uint32(uint256(logs[i].topics[1]));
            }
        }
    }

    function _allRegistrations(Vm.Log[] memory logs) private view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED) ++n;
        }
    }

    function _assertIdTruth(address who, uint32 id) private view {
        assertGt(id, 0, "registered");
        assertEq(game.walletIdOf(who), id, "walletIdOf");
        assertEq(game.walletIdOf(who), id, "mint word carries the ID");
        assertEq(
            address(uint160(uint256(vm.load(address(game), GameSlotKeys.walletElement(id))))),
            who,
            "wallet-table element holds the key"
        );
    }

    function _credited(Vm.Log[] memory logs, uint32 id) private view returns (uint256 total, uint256 events) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != STAKE_UPDATED) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            total += amount;
            ++events;
        }
    }

    function _assertNoElementReads(uint32[] memory ids) private {
        (bytes32[] memory reads,) = vm.accesses(address(game));
        for (uint256 j; j < ids.length; ++j) {
            bytes32 slot = GameSlotKeys.walletElement(ids[j]);
            for (uint256 i; i < reads.length; ++i) {
                assertTrue(reads[i] != slot, "no wallet-table read for an entrant ID");
            }
        }
    }

    // =====================================================================
    // 7. Samplers return lane IDs
    // =====================================================================

    function _expectedTraitSample(uint24 lvl, uint8 trait, uint256 len, uint256 entropy)
        private view returns (uint32[] memory out)
    {
        uint256 take = len > 4 ? 4 : len;
        out = new uint32[](take);
        PackedTicketSampleLib.Cursor memory c;
        PackedTicketSampleLib.begin(c, len, entropy >> 40);
        for (uint256 i; i < take; ++i) {
            (uint256 index,) = PackedTicketSampleLib.next(c, len);
            out[i] = ext.x_bucketIdAt(lvl, trait, index);
        }
    }

    function testFuzz_SampleTraitEntriesReturnsLaneIds(uint256 entropy, uint8 n) public {
        uint256 count = bound(n, 1, 21);
        uint24 lvl = game.level() + 1;
        uint8 trait = uint8(entropy >> 24);
        for (uint256 i; i < count; ++i) {
            (, uint32 id) = _wallet(string(abi.encodePacked("trait_entry_", vm.toString(i))));
            ext.x_bucketAppend(lvl, trait, id, 1);
        }

        (uint8 traitSel, uint32[] memory entries) = game.sampleTraitEntries(true, entropy);

        assertEq(traitSel, trait, "trait selection");
        uint256 len = ext.x_bucketLength(lvl, trait);
        assertGe(len, count, "fixture: seeded lanes present");
        uint32[] memory expected = _expectedTraitSample(lvl, trait, len, entropy);
        assertEq(entries.length, expected.length, "take");
        for (uint256 i; i < entries.length; ++i) {
            assertEq(entries[i], expected[i], "entry = the drawn lane's wallet ID");
            assertTrue(
                uint256(vm.load(address(game), GameSlotKeys.walletElement(entries[i]))) != 0,
                "entry is an allocated wallet ID"
            );
        }
    }

    function test_SampleTraitEntriesEmptyAndRetired() public {
        uint256 entropy = uint256(keccak256("sampler_empty"));
        uint24 lvl = game.level() + 1;
        uint8 trait = uint8(entropy >> 24);
        (uint8 t, uint32[] memory entries) = game.sampleTraitEntries(true, entropy);
        assertEq(t, trait, "trait selection");
        assertEq(entries.length, 0, "empty bucket returns no entries");

        (, uint32 id) = _wallet("retired_entry");
        ext.x_bucketAppend(lvl, trait, id, 3);
        (, entries) = game.sampleTraitEntries(true, entropy);
        assertEq(entries.length, 3, "a live bucket samples");
        // A later same-parity level takes over the buffer: the level is retired.
        ext.x_setTicketBufferLevel(lvl + 2);
        (, entries) = game.sampleTraitEntries(true, entropy);
        assertEq(entries.length, 0, "a retired level returns no entries");
    }

    function _expectedFarFuture(uint256 entropy, uint24 fromLevel, uint24 toLevel)
        private view returns (uint32[] memory t)
    {
        uint256 span = uint256(toLevel - fromLevel) + 1;
        t = new uint32[](8);
        uint256 packs;
        for (uint256 attempt; packs < 4 && attempt < 12; ++attempt) {
            entropy = EntropyLib.hash2(entropy, attempt);
            uint24 target = uint24(fromLevel + entropy % span);
            uint24 key = ext.x_ffKey(target);
            uint256 len = ext.x_tqLen(key);
            if (len == 0) continue;
            uint256 a = (entropy >> 64) % len;
            t[packs] = ext.x_tqLaneAt(key, a);
            uint256 window = len < 8 ? len : 8;
            if (window > 1) {
                uint256 b = (a + 1 + ((entropy >> 128) % (window - 1))) % len;
                t[packs + 4] = ext.x_tqLaneAt(key, b);
            }
            ++packs;
        }
    }

    function testFuzz_SampleFarFutureTicketsReturnsLaneIds(uint256 entropy) public {
        uint24 base = 5;
        // Levels base..base+5 (inside the 100-level far-future ring), emptied first: two empty,
        // one single-lane, three multi-lane queues.
        uint256[6] memory lens = [uint256(0), 1, 11, 0, 3, 9];
        uint256 k;
        for (uint256 l; l < 6; ++l) {
            uint24 key = ext.x_ffKey(base + uint24(l));
            ext.x_tqReset(key);
            for (uint256 i; i < lens[l]; ++i) {
                (, uint32 id) = _wallet(string(abi.encodePacked("ff_", vm.toString(k++))));
                ext.x_tqAppend(key, id);
            }
        }
        uint32[] memory got = game.sampleFarFutureTickets(entropy, base, base + 5);
        uint32[] memory want = _expectedFarFuture(entropy, base, base + 5);
        assertEq(got.length, 8, "eight slots");
        for (uint256 i; i < 8; ++i) assertEq(got[i], want[i], "slot = the drawn lane's wallet ID");
    }

    function test_SampleFarFutureUnfilledSlotsAreZero() public {
        // Levels past the ring window read as empty queues: every slot stays 0.
        uint24 base = 201;
        for (uint24 l = base; l <= base + 3; ++l) assertEq(ext.x_tqLen(ext.x_ffKey(l)), 0, "fixture: no live queue");
        uint32[] memory none = game.sampleFarFutureTickets(uint256(keccak256("ff_none")), base, base + 3);
        for (uint256 i; i < 8; ++i) assertEq(none[i], 0, "no queue: zero slot");

        // One single-lane queue: first-round slots hold its ID, second-round slots stay 0.
        uint24 single = 20;
        (, uint32 id) = _wallet("ff_single");
        ext.x_tqReset(ext.x_ffKey(single));
        ext.x_tqAppend(ext.x_ffKey(single), id);
        assertEq(ext.x_tqLen(ext.x_ffKey(single)), 1, "fixture: one lane");
        uint32[] memory one = game.sampleFarFutureTickets(uint256(keccak256("ff_one")), single, single);
        for (uint256 i; i < 4; ++i) assertEq(one[i], id, "first round: the lane's ID");
        for (uint256 i = 4; i < 8; ++i) assertEq(one[i], 0, "single lane: second round unfilled");
    }

    // =====================================================================
    // 8. Jackpot battle field carries IDs; the Game decodes nothing
    // =====================================================================

    function test_JackpotBattleFieldCarriesQueueIds() public {
        JackpotBattleStub stub = JackpotBattleStub(ContractAddresses.CRAPS);
        vm.etch(ContractAddresses.CRAPS, type(JackpotBattleStub).runtimeCode);
        stub.setRemaining(12);
        uint24 lvl = game.level();
        // Seed one far-future level with distinct entrants; give some a saved board.
        uint24 target = lvl + 40;
        uint32[] memory ids = new uint32[](16);
        for (uint256 i; i < ids.length; ++i) {
            (, ids[i]) = _wallet(string(abi.encodePacked("battle_", vm.toString(i))));
            ext.x_tqAppend(ext.x_ffKey(target), ids[i]);
            if (i % 3 == 0) {
                uint256 board = (uint256(i + 1) << CrapsPreferenceLib.SHIFT) & CrapsPreferenceLib.MASK;
                stub.setSaved(keccak256(abi.encode(ids[i], CrapsPreferenceLib.PASS_SLOT)), bytes32(board | 1));
            }
        }

        vm.record();
        ext.x_delegate(
            ContractAddresses.GAME_JACKPOT_DRAW_MODULE,
            abi.encodeCall(
                DegenerusGameJackpotDrawModule.runPurchaseJackpotBattle,
                (lvl, uint256(keccak256("battle_word")), 30_000_000)
            )
        );
        _assertNoElementReads(ids);

        uint256[] memory field = stub.fieldOf();
        assertEq(field.length, 12, "the chunk filled the remaining seats");
        for (uint256 i; i < field.length; ++i) {
            uint256 w = field[i];
            uint32 id = uint32(w);
            assertEq(w >> 180, 1, "one unit");
            assertEq((w >> 32) & ((uint256(1) << 128) - 1), 0, "bits 32..159 zero");
            // The ID must be a queue lane at an eligible level (seeded or protocol-queued).
            bool lane;
            for (uint24 l = lvl + 1; l <= lvl + 99 && !lane; ++l) {
                uint24 key = ext.x_ffKey(l);
                uint256 len = ext.x_tqLen(key);
                for (uint256 k; k < len && !lane; ++k) lane = ext.x_tqLaneAt(key, k) == id;
            }
            assertTrue(lane, "field word names a queue lane ID");
            uint256 saved;
            for (uint256 j; j < ids.length; ++j) {
                if (ids[j] == id && j % 3 == 0) saved = (uint256(j + 1) << CrapsPreferenceLib.SHIFT) & CrapsPreferenceLib.MASK;
            }
            assertEq((w >> 160) & ((uint256(1) << 20) - 1), saved >> CrapsPreferenceLib.SHIFT, "board read by the ID");
        }
    }

    // =====================================================================
    // 9. payRecordSdgnrs
    // =====================================================================

    function test_PayRecordSdgnrsCoinflipOnly() public {
        (, uint32 id) = _wallet("record_access");
        vm.prank(makeAddr("not_coinflip"));
        vm.expectRevert(DegenerusGameStorage.Unauthorized.selector);
        game.payRecordSdgnrs(id, 100);
    }

    function test_PayRecordSdgnrsZeroShareNamesPayeeWithoutPoolRead() public {
        (address holder, uint32 id) = _wallet("record_bare");
        vm.expectCall(address(sdgnrs), abi.encodeWithSelector(IsDGNRS.poolBalance.selector), 0);
        vm.prank(ContractAddresses.COINFLIP);
        (uint256 paid, address payee) = game.payRecordSdgnrs(id, 0);
        assertEq(paid, 0, "zero share pays nothing");
        assertEq(payee, holder, "payee named on a zero share");
        vm.prank(ContractAddresses.COINFLIP);
        (, payee) = game.payRecordSdgnrs(1, 0);
        assertEq(payee, ContractAddresses.VAULT, "ID 1 payee");
    }

    function test_PayRecordSdgnrsPaysPayee() public {
        (address holder, uint32 id) = _wallet("record_paid");
        uint256 pool = IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Reward);
        assertGt(pool, 0, "fixture: reward pool funded");
        uint256 before = sdgnrs.balanceOf(holder);
        vm.prank(ContractAddresses.COINFLIP);
        (uint256 paid, address payee) = game.payRecordSdgnrs(id, 2_500);
        assertEq(payee, holder, "payee named on a payout");
        assertEq(paid, pool * 2_500 / (10_000 * 500), "1/500-scale share");
        assertGt(paid, 0, "fixture: nonzero payout");
        assertEq(sdgnrs.balanceOf(holder) - before, paid, "payee received the payout");
    }

    function test_PayRecordSdgnrsZeroPayoutNamesPayeeWithoutTransfer() public {
        (address holder, uint32 id) = _wallet("record_dust");
        vm.mockCall(
            address(sdgnrs),
            abi.encodeWithSelector(IsDGNRS.poolBalance.selector, IsDGNRS.Pool.Reward),
            abi.encode(uint256(4_999))
        );
        vm.expectCall(address(sdgnrs), abi.encodeWithSelector(IsDGNRS.transferFromPool.selector), 0);
        vm.prank(ContractAddresses.COINFLIP);
        (uint256 paid, address payee) = game.payRecordSdgnrs(id, 1);
        assertEq(paid, 0, "zero payout pays nothing");
        assertEq(payee, holder, "payee named on a zero payout");
    }

    function test_PayRecordSdgnrsEmptyPoolNamesPayeeWithoutTransfer() public {
        (address holder, uint32 id) = _wallet("record_empty");
        vm.mockCall(
            address(sdgnrs),
            abi.encodeWithSelector(IsDGNRS.poolBalance.selector, IsDGNRS.Pool.Reward),
            abi.encode(uint256(0))
        );
        vm.expectCall(address(sdgnrs), abi.encodeWithSelector(IsDGNRS.transferFromPool.selector), 0);
        vm.prank(ContractAddresses.COINFLIP);
        (uint256 paid, address payee) = game.payRecordSdgnrs(id, 10_000);
        assertEq(paid, 0, "empty pool pays nothing");
        assertEq(payee, holder, "payee named on an empty pool");
    }

    // =====================================================================
    // 10. creditMiddayRng
    // =====================================================================

    function test_CreditMiddayRngReturnsDonorId() public {
        address donor = makeAddr("midday_donor");
        uint256 lengthBefore = _walletsLength();

        vm.prank(makeAddr("not_admin"));
        vm.expectRevert();
        game.creditMiddayRng(donor, 1 ether);

        vm.recordLogs();
        vm.prank(ContractAddresses.ADMIN);
        uint32 id = game.creditMiddayRng(donor, 1 ether);
        (uint256 n, uint32 regId) = _registrations(vm.getRecordedLogs(), donor);
        assertEq(n, 1, "new donor registered once");
        assertEq(id, regId, "returns the new ID");
        assertEq(id, lengthBefore, "ID = prior table length");
        _assertIdTruth(donor, id);
        assertEq(game.middayRngCredits(donor), 1 ether, "credit keyed by the ID");

        vm.recordLogs();
        vm.prank(ContractAddresses.ADMIN);
        uint32 again = game.creditMiddayRng(donor, 2 ether);
        assertEq(again, id, "existing donor: same ID");
        assertEq(_allRegistrations(vm.getRecordedLogs()), 0, "no second registration");
        assertEq(game.middayRngCredits(donor), 3 ether, "credit accumulates");

        // Past paid admission a new donor is refused; an existing one still credits.
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAID_ADMISSION_WALLETS + 1));
        vm.prank(ContractAddresses.ADMIN);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.creditMiddayRng(makeAddr("midday_late_donor"), 1 ether);
        vm.prank(ContractAddresses.ADMIN);
        assertEq(game.creditMiddayRng(donor, 1 ether), id, "existing donor past admission");
    }

    // =====================================================================
    // 11. playerActivityScoreCached
    // =====================================================================

    function test_ActivityScoreCachedReturnsIdOnBothPaths() public {
        // Unregistered: ID 0, nothing registered.
        address stranger = makeAddr("score_stranger");
        uint256 lengthBefore = _walletsLength();
        vm.recordLogs();
        (uint256 s0, uint32 id0) = game.playerActivityScoreCached(stranger);
        assertEq(id0, 0, "unregistered wallet: ID 0");
        assertEq(_allRegistrations(vm.getRecordedLogs()), 0, "no registration");
        assertEq(_walletsLength(), lengthBefore, "table unchanged");
        assertEq(game.walletIdOf(stranger), 0, "still unregistered");
        (uint256 v0,) = game.playerActivityScore(stranger);
        assertEq(s0, v0, "score matches the view");

        // Hot path without history: a registered wallet that never bought.
        (address idle, uint32 idleId) = _wallet("score_idle");
        vm.record();
        (uint256 s1, uint32 id1) = game.playerActivityScoreCached(idle);
        (, bytes32[] memory writes) = vm.accesses(address(game));
        assertEq(writes.length, 0, "hot path writes nothing");
        assertEq(id1, idleId, "hot path returns the ID");
        (uint256 v1,) = game.playerActivityScore(idle);
        assertEq(s1, v1, "hot path score");

        // Cold path: a buyer whose affiliate cache is for another level.
        address buyer = makeAddr("score_buyer");
        vm.deal(buyer, 10 ether);
        uint256 value = 4 * PriceLookupLib.priceForLevel(game.level() + 1);
        vm.prank(buyer);
        game.purchase{value: value}(0, 1_600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint32 buyerId = game.walletIdOf(buyer);
        bytes32 mintSlot = GameSlotKeys.mintPacked(buyer);
        uint256 word = uint256(vm.load(address(game), mintSlot));
        uint256 levelMask = BitPackingLib.MASK_24 << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT;
        vm.store(address(game), mintSlot, bytes32((word & ~levelMask) | (uint256(77) << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT)));
        vm.record();
        (uint256 s2, uint32 id2) = game.playerActivityScoreCached(buyer);
        (, writes) = vm.accesses(address(game));
        bool refreshed;
        for (uint256 i; i < writes.length; ++i) if (writes[i] == mintSlot) refreshed = true;
        assertTrue(refreshed, "cold path refreshed the cache");
        assertEq(id2, buyerId, "cold path returns the ID");
        (uint256 v2,) = game.playerActivityScore(buyer);
        assertEq(s2, v2, "cold path score");
        assertEq(game.walletIdOf(buyer), buyerId, "ID survives the refresh");

        // Hot path cache hit after the refresh.
        vm.record();
        (uint256 s3, uint32 id3) = game.playerActivityScoreCached(buyer);
        (, writes) = vm.accesses(address(game));
        assertEq(writes.length, 0, "cache hit writes nothing");
        assertEq(id3, buyerId, "cache hit returns the ID");
        assertEq(s3, s2, "cache hit score");
    }

    // =====================================================================
    // 12. Afking callbacks by ID
    // =====================================================================

    function test_AfkingCallbacksKeyById() public {
        vm.warp(block.timestamp + 10 days);
        (, uint32 id) = _wallet("afk_callback");
        uint24 today = ext.x_today();
        ext.x_setSub(id, 1, today - 2, today - 1, 5, 7);

        vm.prank(makeAddr("not_quests"));
        vm.expectRevert();
        game.recordAfkingSecondary(id, 1);
        vm.prank(makeAddr("not_quests"));
        vm.expectRevert();
        game.floorAfkingStreakBase(id, 1);

        vm.prank(ContractAddresses.QUESTS);
        game.recordAfkingSecondary(id, 3);
        assertEq(ext.x_streakBase(id), 8, "secondary bumps the ID's base");
        vm.prank(ContractAddresses.QUESTS);
        game.floorAfkingStreakBase(id, 20);
        assertEq(ext.x_streakBase(id), 20, "floor raises the ID's base");
        vm.prank(ContractAddresses.QUESTS);
        game.floorAfkingStreakBase(id, 10);
        assertEq(ext.x_streakBase(id), 20, "floor never lowers");

        // ID 0 and a non-live run: no write at all.
        (, uint32 idle) = _wallet("afk_not_live");
        ext.x_setSub(idle, 1, 0, 0, 4, 9);
        vm.record();
        vm.startPrank(ContractAddresses.QUESTS);
        game.recordAfkingSecondary(0, 3);
        game.floorAfkingStreakBase(0, 50);
        game.recordAfkingSecondary(idle, 3);
        game.floorAfkingStreakBase(idle, 50);
        vm.stopPrank();
        (, bytes32[] memory writes) = vm.accesses(address(game));
        assertEq(writes.length, 0, "no-op for ID 0 and a non-live run");
        assertEq(ext.x_streakBase(idle), 4, "non-live base unchanged");
        assertEq(uint256(vm.load(address(game), GameSlotKeys.byId(0, GameSlots.SUB_OF))), 0, "nothing under ID 0");
    }

    // =====================================================================
    // 13. Degenerette: referrer leg, gift funder registration, self bet
    // =====================================================================

    function _place(address caller, address player, uint8 currency, uint128 perSpin, uint8 spins, uint256 value) private {
        uint32 id = (player == address(0) || player == caller) ? 0 : game.walletIdOf(player);
        vm.prank(caller);
        game.placeDegeneretteBet{value: value}(id, currency, perSpin, spins, SYMBOL);
    }

    /// @dev Deliver `word` for the cohort at IDX (as DegeneretteSweep does) and resolve it.
    function _resolve(uint256 word) private returns (Vm.Log[] memory logs) {
        RecyclingState.seedWord(address(game), IDX, bytes32(word));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        vm.recordLogs();
        vm.prank(makeAddr("degen_crank"));
        game.mineFlip();
        logs = vm.getRecordedLogs();
    }

    /// @dev A word whose 25-spin ETH bet at IDX holds a score-6+ spin (a high-match box share).
    function _highMatchWord(uint256 salt) private pure returns (uint256 word) {
        for (uint256 k; k < 4_000; ++k) {
            word = uint256(keccak256(abi.encode("degen_high_match", salt, k)));
            for (uint8 s; s < 25; ++s) {
                (uint8 score,) = Ref.score(Ref.player(word, uint32(IDX), SYMBOL, s, false), Ref.house(word, uint32(IDX), s, false));
                if (score >= 6) return word;
            }
        }
        revert("no high-match word");
    }

    function _referrerCase(uint256 salt) private returns (Vm.Log[] memory logs, uint32 playerId) {
        (address player, uint32 pid) = _wallet("degen_referred");
        vm.deal(player, 10 ether);
        _place(player, player, ETH, 0.01 ether, 25, 0.25 ether);
        logs = _resolve(_highMatchWord(salt));
        playerId = pid;
    }

    function test_DegeneretteReferrerLegCreditsReferrerId() public {
        (, uint32 rid) = _wallet("degen_referrer");
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.getReferrerIdById.selector),
            abi.encode(rid)
        );
        vm.expectCall(address(coinflip), abi.encodeWithSelector(ICoinflip.creditFlip.selector, rid));
        (Vm.Log[] memory logs,) = _referrerCase(1);
        (uint256 credited, uint256 events) = _credited(logs, rid);
        assertEq(events, 1, "one referrer credit");
        assertGt(credited, 0, "referrer credited by ID");
        (, uint256 vaultEvents) = _credited(logs, 1);
        assertEq(vaultEvents, 0, "a referred player's leg never reaches the VAULT");
    }

    function test_DegeneretteUnreferredLegCreditsVaultId() public {
        vm.expectCall(address(coinflip), abi.encodeWithSelector(ICoinflip.creditFlip.selector, uint32(1)));
        (Vm.Log[] memory logs,) = _referrerCase(1);
        (uint256 credited,) = _credited(logs, 1);
        assertGt(credited, 0, "unreferred: VAULT (ID 1) credited");
    }

    function test_DegeneretteUnregisteredReferrerCreditsNobody() public {
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.getReferrerIdById.selector),
            abi.encode(uint32(0))
        );
        vm.expectCall(address(coinflip), abi.encodeWithSelector(ICoinflip.creditFlip.selector, uint32(0)));
        (Vm.Log[] memory logs,) = _referrerCase(1);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip) && logs[i].topics[0] == STAKE_UPDATED) {
                uint32 id = uint32(uint256(logs[i].topics[1]));
                assertTrue(id != 0 && id != 1, "no credit for the unregistered referrer, none to the VAULT");
            }
        }
    }

    function test_GiftBetRegistersFunderOnce() public {
        (address player, uint32 pid) = _wallet("gift_recipient");
        address funder = makeAddr("gift_funder");
        vm.deal(funder, 10 ether);
        uint32 expectedFunderId = uint32(_walletsLength());
        uint256 totalBet = 0.02 ether;
        vm.expectCall(
            address(quests),
            abi.encodeCall(IDegenerusQuests.handleDegenerette, (expectedFunderId, totalBet, true, PriceLookupLib.priceForLevel(game.level() + 1)))
        );
        vm.recordLogs();
        _place(funder, player, ETH, 0.01 ether, 2, totalBet);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 n, uint32 fid) = _registrations(logs, funder);
        assertEq(n, 1, "funder registered exactly once");
        assertEq(fid, expectedFunderId, "funder's new ID");
        assertEq(_allRegistrations(logs), 1, "nobody else registered");
        _assertIdTruth(funder, fid);
        assertEq(uint32(game.degeneretteBetInfo(IDX, 1)), pid, "the bet belongs to the recipient's ID");
    }

    function test_GiftFlipBetStrayEthLandsInFunderAfkingById() public {
        (address player,) = _wallet("gift_flip_recipient");
        address funder = makeAddr("gift_flip_funder");
        vm.deal(funder, 1 ether);
        vm.prank(address(game));
        coin.mintForGame(funder, 100_000);
        vm.recordLogs();
        _place(funder, player, FLIP, 1_000, 1, 0.003 ether);
        (uint256 n, uint32 fid) = _registrations(vm.getRecordedLogs(), funder);
        assertEq(n, 1, "FLIP gift funder registered once");
        _assertIdTruth(funder, fid);
        assertEq(game.afkingFundingOf(funder), 0.003 ether, "stray ETH in the funder's afking balance");
        assertEq(uint128(uint256(vm.load(address(game), GameSlotKeys.balances(fid))) >> 128), 0.003 ether, "keyed by the funder ID");
    }

    function test_GiftFromRegisteredFunderRegistersNobody() public {
        (address player,) = _wallet("gift2_recipient");
        (address funder,) = _wallet("gift2_funder");
        vm.deal(funder, 10 ether);
        vm.recordLogs();
        _place(funder, player, ETH, 0.01 ether, 1, 0.01 ether);
        assertEq(_allRegistrations(vm.getRecordedLogs()), 0, "no registration");
    }

    function test_GiftPastPaidAdmissionNeedsAdmissionSpend() public {
        (address player,) = _wallet("gift3_recipient");
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAID_ADMISSION_WALLETS + 1));
        address small = makeAddr("gift3_small_funder");
        vm.deal(small, 10 ether);
        uint32 playerId = game.walletIdOf(player);
        vm.prank(small);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.placeDegeneretteBet{value: 0.01 ether}(playerId, ETH, 0.01 ether, 1, SYMBOL);

        address large = makeAddr("gift3_large_funder");
        vm.deal(large, 10 ether);
        _place(large, player, ETH, 0.01 ether, 4, 0.04 ether);
        assertEq(game.walletIdOf(large), PAID_ADMISSION_WALLETS + 1, "an admission-sized gift registers");
    }

    function test_SelfBetRegistersOnceAndQuestsById() public {
        address player = makeAddr("self_bettor");
        vm.deal(player, 10 ether);
        uint32 expectedId = uint32(_walletsLength());
        vm.expectCall(
            address(quests),
            abi.encodeCall(IDegenerusQuests.handleDegenerette, (expectedId, 0.01 ether, true, PriceLookupLib.priceForLevel(game.level() + 1)))
        );
        vm.recordLogs();
        _place(player, address(0), ETH, 0.01 ether, 1, 0.01 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 n, uint32 id) = _registrations(logs, player);
        assertEq(n, 1, "self bettor registered once");
        assertEq(_allRegistrations(logs), 1, "only the bettor");
        assertEq(id, expectedId, "new ID");
        _assertIdTruth(player, id);
    }

    // =====================================================================
    // 14. Deity chain by referrer IDs
    // =====================================================================

    function _deityBuy(address buyer, uint8 symbol) private returns (Vm.Log[] memory logs) {
        vm.deal(buyer, 100 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseDeityPass{value: 100 ether}(0, symbol, bytes32(0));
        logs = vm.getRecordedLogs();
    }

    function test_DeityChainPaysHopPayeesAndConfersPassOnAffiliateId() public {
        address buyer = makeAddr("deity_chain_buyer");
        (address a, uint32 aId) = _wallet("deity_chain_affiliate");
        (address u1, uint32 u1Id) = _wallet("deity_chain_upline1");
        (address u2, uint32 u2Id) = _wallet("deity_chain_upline2");
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.referrerIdsById.selector),
            abi.encode(aId, u1Id, u2Id)
        );
        uint256 reserve = IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Affiliate);
        assertGt(reserve, 0, "fixture: affiliate pool funded");
        uint256 directShare = reserve * 5_000 / 1_000_000;
        uint256 uplineShare = reserve * 1_000 / 1_000_000;
        uint256 aBefore = sdgnrs.balanceOf(a);
        uint256 u1Before = sdgnrs.balanceOf(u1);
        uint256 u2Before = sdgnrs.balanceOf(u2);
        assertEq(game.mintPackedFor(a) >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT & BitPackingLib.MASK_24, 0, "fixture: no pass");

        Vm.Log[] memory logs = _deityBuy(buyer, 3);

        assertEq(sdgnrs.balanceOf(a) - aBefore, directShare, "direct hop paid at its payee");
        assertEq(sdgnrs.balanceOf(u1) - u1Before, uplineShare, "upline 1 paid at its payee");
        assertEq(sdgnrs.balanceOf(u2) - u2Before, uplineShare / 2, "upline 2 paid at its payee");
        uint256 affiliateRanges;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == ENTRIES_QUEUED_RANGE
                && uint32(uint256(logs[i].topics[1])) == aId) ++affiliateRanges;
        }
        assertGt(affiliateRanges, 0, "conferred pass queued on the affiliate's ID");
        assertGt(game.entriesOwedView(game.level() + 1, a), 0, "affiliate owes entries at the pass level");
        assertGt(
            game.mintPackedFor(a) >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT & BitPackingLib.MASK_24,
            0,
            "pass stats on the affiliate's key"
        );
    }

    function test_DeityChainSkipsZeroUplineHops() public {
        address buyer = makeAddr("deity_skip_buyer");
        (address a, uint32 aId) = _wallet("deity_skip_affiliate");
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.referrerIdsById.selector),
            abi.encode(aId, uint32(0), uint32(0))
        );
        uint256 reserve = IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Affiliate);
        uint256 directShare = reserve * 5_000 / 1_000_000;
        uint256 aBefore = sdgnrs.balanceOf(a);

        _deityBuy(buyer, 4);

        assertEq(sdgnrs.balanceOf(a) - aBefore, directShare, "direct hop paid");
        assertEq(reserve - IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Affiliate), directShare, "zero hops pay nothing");
    }

    function test_DeityChainDirectAffiliateWithoutIdReverts() public {
        address buyer = makeAddr("deity_noid_buyer");
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.referrerIdsById.selector),
            abi.encode(uint32(0), uint32(0), uint32(0))
        );
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.purchaseDeityPass{value: 100 ether}(0, 5, bytes32(0));
    }

    // =====================================================================
    // O8/H6. A code owner registered inside a purchase keeps ID truth
    // =====================================================================

    /// @dev A default (address) code whose owner has no ID registers that owner inside the
    ///      purchase's affiliate call. Nothing later in the purchase may write back a stale copy
    ///      of the owner's mint word: afterwards both directions of the owner's ID still agree.
    function _assertOwnerRegisteredMidPurchase(uint256 kind) private {
        address buyer = makeAddr(string(abi.encodePacked("h6_buyer_", vm.toString(kind))));
        address owner = makeAddr(string(abi.encodePacked("h6_owner_", vm.toString(kind))));
        bytes32 code = bytes32(uint256(uint160(owner)));
        vm.deal(buyer, 200 ether);
        uint256 price = PriceLookupLib.priceForLevel(game.level() + 1);
        vm.recordLogs();
        vm.startPrank(buyer);
        if (kind == 0) game.purchase{value: 4 * price}(0, 1_600, 0, code, MintPaymentKind.DirectEth, false);
        else if (kind == 1) game.purchaseWhalePass{value: 4 ether}(0, 1, code);
        else if (kind == 2) game.purchaseLazyPass{value: 1 ether}(0, code);
        else if (kind == 3) game.purchase{value: 10 * price}(0, 0, 0, code, MintPaymentKind.DirectEth, true);
        else game.purchaseDeityPass{value: 100 ether}(0, 7, code);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 n, uint32 ownerId) = _registrations(logs, owner);
        assertEq(n, 1, "the code owner registered inside the purchase");
        _assertIdTruth(owner, ownerId);
        (n,) = _registrations(logs, buyer);
        assertEq(n, 1, "the buyer registered");
        _assertIdTruth(buyer, game.walletIdOf(buyer));
        if (kind == 4) {
            // The deity pass confers its whale pass on the owner's ID and key.
            assertGt(
                game.mintPackedFor(owner) >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT & BitPackingLib.MASK_24,
                0,
                "pass stats re-read the owner's word"
            );
        }
    }

    function test_H6_TicketPurchaseOwnerKeepsIdTruth() public { _assertOwnerRegisteredMidPurchase(0); }
    function test_H6_WhalePassOwnerKeepsIdTruth() public { _assertOwnerRegisteredMidPurchase(1); }
    function test_H6_LazyPassOwnerKeepsIdTruth() public { _assertOwnerRegisteredMidPurchase(2); }
    function test_H6_FoilPackOwnerKeepsIdTruth() public { _assertOwnerRegisteredMidPurchase(3); }
    function test_H6_DeityPassOwnerKeepsIdTruth() public { _assertOwnerRegisteredMidPurchase(4); }

    // =====================================================================
    // 15. Mint: creditFlipPair by IDs; redeemFlip quest and queue by the new ID
    // =====================================================================

    function test_PurchaseCreditsPairByIds() public {
        (address buyer, uint32 buyerId) = _wallet("pair_ids_buyer");
        (, uint32 winnerId) = _wallet("pair_ids_winner");
        vm.deal(buyer, 10 ether);
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(IDegenerusQuests.handlePurchase.selector),
            abi.encode(uint256(0), uint8(0), uint32(0), false, false)
        );
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.payAffiliateCombined.selector),
            abi.encode(winnerId, uint256(500), uint256(300))
        );
        // The call carries the buyer ID first and the returned winner ID with its credit.
        uint256 value = 4 * PriceLookupLib.priceForLevel(game.level() + 1);
        vm.expectCall(address(coinflip), abi.encodeWithSelector(ICoinflip.creditFlipPair.selector, buyerId));
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: value}(0, 1_600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        (uint256 winnerCredit,) = _credited(vm.getRecordedLogs(), winnerId);
        assertEq(winnerCredit, 500, "winner leg by its ID");
    }

    function test_RedeemFlipQuestAndQueueByNewId() public {
        address buyer = makeAddr("redeem_new_id");
        vm.prank(address(game));
        coin.mintForGame(buyer, 1_000_000 ether);
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32((pools & ~uint256(type(uint128).max)) | 60 ether));
        uint32 expectedId = uint32(_walletsLength());
        vm.expectCall(
            address(quests),
            abi.encodeWithSelector(IDegenerusQuests.handlePurchase.selector, expectedId, uint256(0))
        );
        vm.recordLogs();
        vm.prank(buyer);
        game.redeemFlip(0, 4_000);
        (uint256 n, uint32 id) = _registrations(vm.getRecordedLogs(), buyer);
        assertEq(n, 1, "FLIP payer registered once");
        assertEq(id, expectedId, "new ID");
        _assertIdTruth(buyer, id);
        uint32 owed;
        for (uint24 l = game.level(); l <= game.level() + 2; ++l) owed += game.entriesOwedView(l, buyer);
        assertGt(owed, 0, "entries queued by the new ID");
    }

    // =====================================================================
    // 16. registerWallet refuses JACKPOT_BATTLE
    // =====================================================================

    function test_RegisterWalletRefusesJackpotBattle() public {
        vm.prank(ContractAddresses.JACKPOT_BATTLE);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.registerWallet(makeAddr("jb_target"), true);
        vm.prank(ContractAddresses.JACKPOT_BATTLE);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.registerWallet(makeAddr("jb_target"), false);

        vm.prank(ContractAddresses.CRAPS);
        uint32 id = game.registerWallet(makeAddr("jb_target"), true);
        assertGt(id, 0, "an allow-listed caller still registers");
    }

    // =====================================================================
    // 17. Lens parity by ID
    // =====================================================================

    function test_LensMirrorsGameActivityScoreById() public {
        vm.warp(block.timestamp + 10 days);
        DegenerusGameLens lens = new DegenerusGameLens();
        (address p, uint32 id) = _wallet("lens_player");
        uint24 today = ext.x_today();
        ext.x_setSub(id, 1, today - 3, today - 1, 7, 3);
        // A stale affiliate cache level: both Game and Lens read the points by ID.
        bytes32 mintSlot = GameSlotKeys.mintPacked(p);
        uint256 word = uint256(vm.load(address(game), mintSlot));
        word = (word & ~(BitPackingLib.MASK_24 << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT))
            | (uint256(77) << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT);
        vm.store(address(game), mintSlot, bytes32(word));
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(IDegenerusQuests.effectiveBaseStreakAndAfking.selector, id),
            abi.encode(uint32(5), true)
        );
        vm.mockCall(
            address(affiliate),
            abi.encodeWithSelector(IDegenerusAffiliate.affiliateBonusPointsBest.selector, game.level(), id),
            abi.encode(uint256(6))
        );

        DegenerusGameLens.SubFull memory s = lens.subInfoFull(address(game), p);
        assertEq(s.effectiveStreak, 9, "live run: base 7 + two funded days");
        assertEq(s.subStreakLatch, 7, "Sub record read by the ID");
        DegenerusGameLens.ActivityBreakdown memory b = lens.activityScoreBreakdown(address(game), p);
        (uint256 total, uint32 gameId) = game.playerActivityScore(p);
        assertEq(gameId, id, "Game returns the ID");
        assertEq(b.total, total, "Lens total is the Game's score");
        assertEq(b.questStreak, s.effectiveStreak, "one effective streak");
        assertEq(b.affiliatePoints, 6, "affiliate points read by the ID");
        uint256 sum = b.mintStreakPoints + b.mintCountPoints + b.questStreakPoints + b.affiliatePoints + b.passBonusPoints;
        assertEq(sum > b.cursePoints ? sum - b.cursePoints : 0, total, "components reproduce the Game's score");
        assertEq(b.questStreakPoints, 4, "quest points = streak / 2");
    }
}
