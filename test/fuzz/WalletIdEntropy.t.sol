// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {DeityBoonViewer} from "../../contracts/DeityBoonViewer.sol";
import {DeityBoonViewerTreeHarness} from "./BoonRollTreeParity.t.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Ticket worker in the Game context: queues by wallet ID, commits a cohort word, drains.
contract WalletIdEntropyHarness is DegenerusGameTicketModule, WalletSeed {
    function initialize(uint24 lvl) external { level = lvl; }

    /// @dev The next registered wallet takes ID `next`.
    function setNextWalletId(uint256 next) external {
        if (wallets.length == 0) wallets.push();
        uint256[] storage w = wallets;
        assembly ("memory-safe") { sstore(w.slot, next) }
    }

    function credit(address player, uint24 lvl, uint32 scaled) external returns (uint32 id) {
        id = _seedWallet(player);
        _queueEntriesScaled(id, lvl, scaled);
    }

    function commit(uint256 word, bool future) external {
        rngWordCurrent = word < 2 ? 2 : word;
        _setRngSessionPublished(true);
        rngLockedFlag = true;
        if (future) {
            earlyTicketLevel = level + 2;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, MID_DAY_FUTURE_POOL);
        } else {
            ticketWriteSlot = !ticketWriteSlot;
            foilWriteSlot = !foilWriteSlot;
            (foilWriteCount, foilReadCount) = (foilReadCount, foilWriteCount);
        }
    }

    function seedBuffer(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function setSnap(uint8 shift) external { snapShift = shift; }

    /// @dev Mark gold six taken at `lvl` with one lane naming wallet `id`.
    function seedGold(uint24 lvl, uint32 id) external { _bucketAppendRun(_traitBufferBase(lvl), GoldSixLib.TRAIT, id, 1, lvl); }

    function seedFoil(address buyer, uint24 lvl) external returns (uint32 id) {
        id = _seedWallet(buyer);
        foilRecord[lvl & 3][id] = (uint256(lvl) << _FOIL_LEVEL_SHIFT) | (uint256(10_000) << _FOIL_MULT_SHIFT);
        uint24 key = _foilWriteKey();
        uint256 i = _foilCount(key);
        uint256 s = _foilSlot(key, i);
        uint256 pack = (uint256(id) << 192) | (uint256(lvl) << 160) | uint160(buyer);
        assembly ("memory-safe") { sstore(s, pack) }
        foilWriteCount = uint32(i + 1);
    }

    function foilRecordOf(uint32 id, uint24 lvl) external view returns (uint256) { return foilRecord[lvl & 3][id]; }
    function register(address who) external returns (uint32) { return _seedWallet(who); }
    function readKey(uint24 lvl) external view returns (uint24) { return _tqReadKey(lvl); }
    function writeKey(uint24 lvl) external view returns (uint24) { return _tqWriteKey(lvl); }
    function futureKey(uint24 lvl) external view returns (uint24) { return _tqFarFutureKey(lvl); }
    function idOf(address who) external view returns (uint32) { return _walletIdOf(who); }
    function owedOf(uint24 key, uint32 id) external view returns (uint80) { return _entryPacked(key, id); }
    function word() external view returns (uint256) { return _lootboxWord(_rngReadBuffer()); }

    /// @dev Ordered bucket lanes (wallet IDs) and entry count of `lvl`.
    function digest(uint24 lvl) external view returns (bytes32 out, uint256 count) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            count += n;
            out = keccak256(abi.encode(out, t, n));
            for (uint256 i; i < n; ++i) out = keccak256(abi.encode(out, _bucketIdAtUnchecked(lvl, uint8(t), i)));
        }
    }

    /// @dev Stored (wallet ID, trait) multiset of `lvl`.
    function inventory(uint24 lvl) external view returns (uint256 inv, uint256 entries) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            entries += n;
            for (uint256 i; i < n; ++i) {
                unchecked { inv += uint256(keccak256(abi.encode(_bucketIdAtUnchecked(lvl, uint8(t), i), uint8(t)))); }
            }
        }
    }
}

/// @dev The engine's survival coin with an integer salt.
contract SurvivalProbe is Craps {
    function survived(bytes32 seed, uint256 n, uint256 salt) external pure returns (bool) {
        return _survived(seed, n, salt);
    }
}

/// @dev Deity menu data source: a fixed seed, day and wallet ID per address.
contract DeityMenuSource {
    uint256 internal seed;
    uint24 internal today;
    mapping(address => uint32) internal ids;
    mapping(uint24 => uint256) internal words;

    function set(uint256 s, uint24 d) external { seed = s; today = d; }
    function setId(address who, uint32 id) external { ids[who] = id; }
    function setWord(uint24 d, uint256 w) external { words[d] = w; }

    function deityBoonData(address) external view returns (uint256, uint24, uint8, bool, bool) {
        return (seed, today, 0, false, false);
    }
    function rngWordForDay(uint24 d) external view returns (uint256) { return words[d]; }
    function walletIdOf(address who) external view returns (uint32) { return ids[who]; }
}

/// @title WalletIdEntropy — exact seed preimages after the wallet-ID swap
/// @notice Every converted randomness input is the committed owner's wallet ID, never the address:
///         the ticket stream identity (solo runs, seats, fractional and far-future remainders),
///         the reveal events, foil lines, the deity menu and the dice survival salt. Each test
///         recomputes the exact preimage and, where an outcome is observable, picks a fixture in
///         which the address-keyed preimage would have produced a different result.
contract WalletIdEntropyTest is Test {
    bytes32 private constant TRAITS_GENERATED = keccak256("TraitsGenerated(uint32,uint256,uint32)");
    uint64 private constant LCG = 6364136223846793005;
    uint256 private constant FULL = 9_000_000;
    WalletIdEntropyHarness private h;

    function setUp() public {
        vm.warp(10 days);
        vm.etch(ContractAddresses.GAME, address(new WalletIdEntropyHarness()).code);
        h = WalletIdEntropyHarness(ContractAddresses.GAME);
        h.initialize(1);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
    }

    function _player(uint256 i) private pure returns (address) { return address(uint160(0x5EED0000 + i)); }

    /// @dev The address-keyed identity the drain used before the swap, for non-vacuity checks.
    function _addressIdentity(uint24 key, uint24 lvl, uint256 qi, address player) private pure returns (uint256) {
        uint8 domain = key & (1 << 22) != 0 ? TicketEntropy.FUTURE
            : key & (1 << 23) != 0 ? TicketEntropy.ORDINARY_ONE : TicketEntropy.ORDINARY_ZERO;
        return (uint256(domain) << 248) | (uint256(lvl) << 224) | (qi << 192) | (uint256(uint160(player)) << 32);
    }

    // ---------------------------------------------------------------------------------------
    // Identity codec
    // ---------------------------------------------------------------------------------------

    function _assertCodec(uint24 key, uint24 lvl, uint256 qi, uint32 id, uint8 domain) private pure {
        uint256 stream = TicketEntropy.identity(key, lvl, qi, id);
        assertEq(stream >> 248, domain, "domain byte");
        assertEq(uint24(stream >> 224), lvl, "level");
        assertEq(uint32(stream >> 192), qi, "physical queue index");
        assertEq(uint32(stream >> TicketEntropy.ID_SHIFT), id, "wallet ID at bits 32..63");
        assertEq((stream >> 64) & type(uint128).max, 0, "bits 64..191 are zero");
        assertEq(uint32(stream), 0, "low 32 bits reserved for the run offset");
        assertEq(stream & TicketEntropy.GOLD_SIX_TAKEN, 0, "event flag never in the identity");
    }

    function test_IdentityCodecPinsWalletIdAt32() public pure {
        assertEq(TicketEntropy.ID_SHIFT, 32);
        uint32[2] memory ids = [uint32(1), type(uint32).max];
        for (uint256 i; i < 2; ++i) {
            _assertCodec(5, 5, 0, ids[i], TicketEntropy.ORDINARY_ZERO);
            _assertCodec(5 | (1 << 23), 5, type(uint32).max, ids[i], TicketEntropy.ORDINARY_ONE);
            _assertCodec(5 | (1 << 22), type(uint24).max, 77, ids[i], TicketEntropy.FUTURE);
        }
        // The maximum ID reaches bit 63 untruncated.
        assertEq(TicketEntropy.identity(5, 5, 0, type(uint32).max) >> 63 & 1, 1);
    }

    function testFuzz_IdentityCodec(uint24 lvl, uint32 qi, uint32 id, bool one, bool future) public pure {
        uint24 key = (lvl & 0x3FFFFF) | (future ? uint24(1 << 22) : 0) | (one ? uint24(1 << 23) : 0);
        uint8 domain = future ? TicketEntropy.FUTURE : one ? TicketEntropy.ORDINARY_ONE : TicketEntropy.ORDINARY_ZERO;
        _assertCodec(key, lvl, qi, id, domain);
    }

    // ---------------------------------------------------------------------------------------
    // Solo runs: the event key is the wallet-ID stream, and its replay is the stored inventory
    // ---------------------------------------------------------------------------------------

    function _soloReplay(uint32 id, uint256 keyed, uint32 take, uint256 entropy)
        private pure returns (uint256 inv)
    {
        bool goldTaken = keyed & TicketEntropy.GOLD_SIX_TAKEN != 0;
        uint256 stream = keyed & ~TicketEntropy.GOLD_SIX_TAKEN & ~uint256(type(uint32).max);
        uint256 i = uint32(keyed);
        uint256 end = i + take;
        while (i < end) {
            uint64 s = uint64(uint256(keccak256(abi.encode(stream, entropy, i >> 4)))) | 1;
            uint64 offset = uint64(i & 15);
            unchecked { s = s * (LCG + offset) + offset; }
            for (uint256 j = offset; j < 16 && i < end; ++j) {
                unchecked { s = s * LCG + 1; }
                uint8 trait = DegenerusTraitUtils.traitFromWord(s) + uint8((i & 3) << 6);
                if (trait == GoldSixLib.TRAIT) {
                    if (goldTaken) trait = GoldSixLib.replacement(s);
                    else goldTaken = true;
                }
                unchecked { inv += uint256(keccak256(abi.encode(id, trait))); }
                ++i;
            }
        }
    }

    /// @dev One owner, solo path; returns (keyed, take) of its single run.
    function _soloRun(uint256 nextId, uint256 entropy) private returns (uint32 id, uint256 keyed, uint32 take) {
        h.setNextWalletId(nextId);
        id = h.credit(_player(0), 1, 4_800); // 48 whole entries: three aligned groups
        assertEq(id, nextId, "fixture wallet ID");
        h.commit(entropy, false);
        vm.recordLogs();
        MineFlipGas.Result memory r = h.runTicketWork(2, FULL);
        assertTrue(r.done, "one call drains the solo owner");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 runs;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].topics[0] != TRAITS_GENERATED) continue;
            assertEq(uint256(logs[i].topics[1]), id, "TraitsGenerated topic is the wallet ID");
            (keyed, take) = abi.decode(logs[i].data, (uint256, uint32));
            ++runs;
        }
        assertEq(runs, 1, "one solo run");
    }

    function _checkSolo(uint256 nextId) private {
        uint256 entropy = uint256(keccak256(abi.encode("solo", nextId)));
        (uint32 id, uint256 keyed, uint32 take) = _soloRun(nextId, entropy);
        assertEq(take, 48);
        uint256 stream = TicketEntropy.identity(h.readKey(1), 1, 0, id);
        assertEq(keyed & ~TicketEntropy.GOLD_SIX_TAKEN, stream, "key = wallet-ID identity at offset 0");
        (uint256 inv, uint256 entries) = h.inventory(1);
        assertEq(entries, take);
        assertEq(_soloReplay(id, keyed, take, entropy), inv, "replay of the ID stream equals the stored inventory");
        // Non-vacuity: the address-keyed stream would have generated a different inventory.
        uint256 addressKeyed = _addressIdentity(h.readKey(1), 1, 0, _player(0)) | (keyed & TicketEntropy.GOLD_SIX_TAKEN);
        assertTrue(_soloReplay(id, addressKeyed, take, entropy) != inv, "address stream differs");
    }

    function test_SoloRunStreamIsWalletId1() public { _checkSolo(1); }

    function test_SoloRunStreamIsWalletIdUint32Max() public { _checkSolo(type(uint32).max); }

    /// @dev Gold six already taken at the level: the event sets bit 255, and the stream hashed for
    ///      generation is the identity with that flag stripped.
    function test_GoldSixFlagIsStrippedBeforeHashing() public {
        h.seedBuffer(1);
        h.setNextWalletId(2);
        uint32 marker = h.register(address(0xF00D));
        h.seedGold(1, marker);
        uint256 entropy = uint256(keccak256("gold-six-flag"));
        h.setNextWalletId(7_000_000);
        uint32 id = h.credit(_player(0), 1, 4_800);
        h.commit(entropy, false);
        (uint256 invBefore, uint256 entriesBefore) = h.inventory(1);
        vm.recordLogs();
        h.runTicketWork(2, FULL);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 keyed;
        uint32 take;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 2 && logs[i].topics[0] == TRAITS_GENERATED) {
                (keyed, take) = abi.decode(logs[i].data, (uint256, uint32));
            }
        }
        assertEq(keyed >> 255, 1, "gold six already taken: event flag set");
        assertEq(keyed & ~TicketEntropy.GOLD_SIX_TAKEN, TicketEntropy.identity(h.readKey(1), 1, 0, id));
        (uint256 inv, uint256 entries) = h.inventory(1);
        assertEq(entries - entriesBefore, take);
        unchecked {
            assertEq(_soloReplay(id, keyed, take, entropy), inv - invBefore, "replay from the stripped stream");
        }
    }

    // ---------------------------------------------------------------------------------------
    // Seats and fractional remainders
    // ---------------------------------------------------------------------------------------

    /// @dev Per-ID revealed entries from both event kinds in `logs`.
    function _countReveals(Vm.Log[] memory logs, uint32[] memory ids, uint24 lvl)
        private pure returns (uint256[] memory counts)
    {
        counts = new uint256[](ids.length);
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length == 2 && l.topics[0] == TRAITS_GENERATED) {
                (, uint32 take) = abi.decode(l.data, (uint256, uint32));
                for (uint256 k; k < ids.length; ++k) if (uint256(l.topics[1]) == ids[k]) counts[k] += take;
                continue;
            }
            if (l.topics.length != 4 || l.data.length != 32) continue;
            uint256 mask = abi.decode(l.data, (uint144)) >> 128;
            for (uint256 j; j < 4; ++j) {
                uint256 topic = uint256(l.topics[j]);
                uint256 nibble = (mask >> (4 * j)) & 15;
                if (nibble == 0) { assertEq(topic, 0, "unused seat topic is zero"); continue; }
                assertEq(topic >> 160, lvl, "level prefix at bit 160");
                assertEq(uint160(topic) >> 32, 0, "seat topic carries a 32-bit wallet ID");
                bool known;
                for (uint256 k; k < ids.length; ++k) {
                    if (uint32(topic) == ids[k]) {
                        known = true;
                        for (uint256 q; q < 4; ++q) if (nibble & (1 << q) != 0) ++counts[k];
                    }
                }
                assertTrue(known, "seat topic names a queued wallet ID");
            }
        }
    }

    /// @dev Queue `n` owners with whole entries plus fractions at `lvl`, find a word where the
    ///      ID and address identities disagree for at least one fraction, drain, and check every
    ///      owner revealed exactly its whole entries plus its ID-keyed fractional draw. A
    ///      far-future pool holds whole entries only: its fractions come from the snap valve
    ///      (`snapShift`), which `_readOwed` applies and then resolves to a whole entry.
    function _remainders(uint24 lvl, bool future, uint256 n, uint32 whole) private {
        uint32[] memory ids = new uint32[](n);
        uint8[] memory fractions = new uint8[](n);
        uint32[] memory wholes = new uint32[](n);
        h.setNextWalletId(1 << 31);
        if (future) h.setSnap(5);
        for (uint256 i; i < n; ++i) {
            if (future) {
                uint256 scaled = (uint256(whole) * (i + 1) * 100) >> 5;
                ids[i] = h.credit(_player(i), lvl, whole * uint32(i + 1) * 100);
                wholes[i] = uint32(scaled / 100);
                fractions[i] = uint8(scaled % 100);
            } else {
                fractions[i] = uint8(17 + (i * 29) % 70);
                wholes[i] = whole;
                ids[i] = h.credit(_player(i), lvl, whole * 100 + fractions[i]);
            }
        }
        // The commit makes the queue the entries were written to the read queue.
        uint24 key = future ? h.futureKey(lvl) : h.writeKey(lvl);
        uint256 entropy = uint256(keccak256(abi.encode("fractions", lvl, future)));
        for (bool differs; !differs; ++entropy) {
            for (uint256 i; i < n && !differs; ++i) {
                differs = TicketEntropy.remainder(TicketEntropy.identity(key, lvl, i, ids[i]), entropy, fractions[i])
                    != TicketEntropy.remainder(_addressIdentity(key, lvl, i, _player(i)), entropy, fractions[i]);
            }
            if (differs) break;
        }
        h.commit(entropy, future);
        assertEq(h.word(), entropy, "committed cohort word");
        vm.recordLogs();
        for (uint256 calls; calls < 40; ++calls) {
            MineFlipGas.Result memory r = h.runTicketWork(future ? 0 : lvl + 1, FULL);
            if (r.done || !r.progressed) break;
        }
        uint256[] memory counts = _countReveals(vm.getRecordedLogs(), ids, lvl);
        for (uint256 i; i < n; ++i) {
            bool win = TicketEntropy.remainder(TicketEntropy.identity(key, lvl, i, ids[i]), entropy, fractions[i]);
            assertEq(counts[i], uint256(wholes[i]) + (win ? 1 : 0), "whole entries plus the ID-keyed fraction");
            assertEq(h.owedOf(key, ids[i]), 0, "entry fully drained");
        }
    }

    /// @dev Eight seated owners exhaust their whole entries in round one and resolve their
    ///      fractions on the seat path.
    function test_SeatFractionsUseWalletIdentity() public { _remainders(1, false, 8, 4); }

    /// @dev Two owners stay on the solo path; the final tail resolves each fraction.
    function test_SoloFractionsUseWalletIdentity() public { _remainders(1, false, 2, 5); }

    /// @dev A far-future pool: `_readOwed` resolves each fraction to a whole entry on read.
    function test_FarFutureFractionsUseWalletIdentity() public { _remainders(3, true, 9, 4); }

    /// @dev The same queue drained in one call and in many small calls stores the same ordered
    ///      wallet-ID lanes; budgets never enter the stream.
    function test_ResumeInvarianceWithHighWalletIds() public {
        h.setNextWalletId(type(uint32).max - 20);
        for (uint256 i; i < 11; ++i) h.credit(_player(i), 1, uint32(1_200 + i * 437));
        h.commit(uint256(keccak256("resume-ids")), false);
        uint256 snap = vm.snapshotState();
        h.runTicketWork(2, FULL);
        (bytes32 full, uint256 count) = h.digest(1);
        assertTrue(vm.revertToStateAndDelete(snap));
        uint256 calls;
        for (; calls < 400; ++calls) {
            MineFlipGas.Result memory r = h.runTicketWork(2, 1_400_000);
            assertTrue(r.progressed, "each bounded call progresses");
            if (r.done) break;
        }
        assertGt(calls, 2, "the small budget split the drain");
        (bytes32 split, uint256 splitCount) = h.digest(1);
        assertEq(splitCount, count);
        assertEq(split, full, "same ordered wallet-ID lanes");
    }

    // ---------------------------------------------------------------------------------------
    // Foil lines and the foil TraitsGenerated key
    // ---------------------------------------------------------------------------------------

    function test_FoilLinesAndKeyUseBuyerWalletId() public {
        h.initialize(2);
        h.seedBuffer(1);
        h.setNextWalletId(type(uint32).max);
        uint32 id = h.seedFoil(address(0xF011), 3);
        assertEq(id, type(uint32).max);
        h.commit(uint256(keccak256("foil-id-word")), false);
        uint256 entropy = h.word();
        vm.recordLogs();
        h.runTicketWork(3, FULL);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].topics[0] != TRAITS_GENERATED) continue;
            (uint256 baseKey, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
            assertEq(uint256(logs[i].topics[1]), id, "foil TraitsGenerated topic is the wallet ID");
            assertEq(baseKey, (uint256(TicketEntropy.FOIL) << 248) | (uint256(3) << 224) | (uint256(id) << 32));
            assertEq(take, 16);
            seen = true;
        }
        assertTrue(seen, "the pack materialized");
        uint256 record = h.foilRecordOf(id, 3);
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(10_000);
        bool goldTaken;
        bool differs;
        for (uint256 i; i < 4; ++i) {
            uint256 seed = uint256(keccak256(abi.encode(entropy, uint256(id), uint24(3), keccak256("foil-seed"), i)));
            uint256 addressSeed = uint256(keccak256(abi.encode(entropy, address(0xF011), uint24(3), keccak256("foil-seed"), i)));
            uint8 tD = DegenerusTraitUtils.foilTrait(uint64(seed >> 192), cut) | 192;
            if (tD == GoldSixLib.TRAIT) {
                if (goldTaken) tD = GoldSixLib.replacement(seed);
                goldTaken = true;
            }
            uint32 line = uint32(DegenerusTraitUtils.foilTrait(uint64(seed), cut))
                | (uint32(DegenerusTraitUtils.foilTrait(uint64(seed >> 64), cut) | 64) << 8)
                | (uint32(DegenerusTraitUtils.foilTrait(uint64(seed >> 128), cut) | 128) << 16)
                | (uint32(tD) << 24);
            assertEq(uint32(record >> (56 + i * 32)), line, "stored line from the ID-keyed foil seed");
            if (uint32(DegenerusTraitUtils.foilTrait(uint64(addressSeed), cut)) != uint8(line)) differs = true;
        }
        assertTrue(differs, "the address-keyed seed would have drawn other lines");
    }

    // ---------------------------------------------------------------------------------------
    // Deity menu
    // ---------------------------------------------------------------------------------------

    function _menu(DeityBoonViewerTreeHarness tree, uint256 seed, uint32 id, uint24 day)
        private view returns (uint8[3] memory slots)
    {
        for (uint8 i; i < 3; ++i) {
            uint256 roll = uint256(keccak256(abi.encode(seed, uint256(id), day, i))) % (2856 - 50 - 40);
            if (roll >= 982) roll += 50;
            if (roll >= 1072) roll += 40;
            slots[i] = tree.tree(roll);
        }
    }

    function test_DeityMenuIsKeyedByDeityWalletId() public {
        DeityBoonViewerTreeHarness viewer = new DeityBoonViewerTreeHarness();
        DeityMenuSource src = new DeityMenuSource();
        address deity = address(0xDE17);
        uint24 day = 41;
        src.set(0xCAFE, day);
        src.setWord(day, 0xBEEF);
        uint32[2] memory ids = [uint32(1), type(uint32).max];
        for (uint256 k; k < 2; ++k) {
            src.setId(deity, ids[k]);
            (uint8[3] memory slots,, uint24 d) = viewer.deityBoonSlots(address(src), deity);
            assertEq(d, day);
            uint8[3] memory expected = _menu(viewer, 0xCAFE, ids[k], day);
            for (uint256 i; i < 3; ++i) assertEq(slots[i], expected[i], "today's menu from the deity ID");
            (uint8[3] memory next, uint24 nextDay) = viewer.deityBoonSlotsTomorrow(address(src), deity);
            assertEq(nextDay, day + 1);
            expected = _menu(viewer, 0xBEEF, ids[k], day + 1);
            for (uint256 i; i < 3; ++i) assertEq(next[i], expected[i], "tomorrow's menu from the deity ID");
        }
        // An address with no wallet ID has no menu.
        src.setId(deity, 0);
        (uint8[3] memory none,,) = viewer.deityBoonSlots(address(src), deity);
        for (uint256 i; i < 3; ++i) assertEq(none[i], 0);
    }

    // ---------------------------------------------------------------------------------------
    // Dice survival salt
    // ---------------------------------------------------------------------------------------

    function test_SurvivalSaltIsAnExactIntegerWord() public {
        SurvivalProbe probe = new SurvivalProbe();
        bytes32 seed = keccak256("survival-salt");
        uint256[4] memory salts = [
            uint256(1),
            uint256(type(uint32).max),
            // A generated Decimator entry's synthetic identity keeps its 160-bit value.
            uint256(uint160(uint256(keccak256(abi.encode(keccak256("decimator.battle.generated.player.v1"), uint256(7), uint24(5), uint64(9)))))),
            uint256(uint160(address(0xBEEF)))
        ];
        for (uint256 k; k < 4; ++k) {
            for (uint256 n; n < 24; ++n) {
                bool expected = uint256(keccak256(abi.encode(uint256(0x537572766976616c), seed, n, salts[k]))) & 1 == 1;
                assertEq(probe.survived(seed, n, salts[k]), expected, "keccak(SURVIVAL_TAG, seed, round, salt)");
            }
        }
        // A 160-bit salt hashes exactly as the address it encodes did.
        address a = address(uint160(salts[2]));
        for (uint256 n; n < 24; ++n) {
            assertEq(
                probe.survived(seed, n, salts[2]),
                uint256(keccak256(abi.encode(uint256(0x537572766976616c), seed, n, a))) & 1 == 1
            );
        }
    }

    /// @dev The engine entry the Decimator calls forwards the salt word unchanged: a wallet-ID salt
    ///      and the same value as a synthetic salt run identically, and distinct IDs run apart.
    function test_EngineBoundedRunTakesTheSaltWord() public {
        CrapsEngine engine = new CrapsEngine();
        bytes32 seed = keccak256("engine-salt");
        uint256 board = uint256(keccak256("engine-board"));
        // Ten 60-FLIP chips stake 600 FLIP: a 450-FLIP bankroll takes the survival coin at once.
        uint256 bank = 450e18;
        Craps.SlipResult memory a = engine.settleSlipBounded(0, 60, board, 10, seed, bank, 1, 0x050c, (511 << 16) | 48);
        Craps.SlipResult memory b = engine.settleSlipBounded(0, 60, board, 10, seed, bank, uint256(uint160(address(1))), 0x050c, (511 << 16) | 48);
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), "salt is the integer word");
        bool apart;
        for (uint256 id = 2; id < 40 && !apart; ++id) {
            Craps.SlipResult memory c = engine.settleSlipBounded(0, 60, board, 10, seed, bank, id, 0x050c, (511 << 16) | 48);
            apart = keccak256(abi.encode(c)) != keccak256(abi.encode(a));
        }
        assertTrue(apart, "different wallet IDs season different survival coins");
    }
}
