// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {GameSlots} from "../helpers/GameSlots.sol";

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @title StorageCensus -- per-transaction storage-creation census on the real deployment
/// @notice Runs one top-level call ("transaction") under state-diff and mapping recording and logs
///         every slot it CREATES (zero -> nonzero) or CLEARS (nonzero -> zero), attributed to the
///         storage root that owns it. scripts/audit/storage-census/aggregate.py parses the logs.
/// @dev Counting rules (STORAGE-REUSE-PHASE2 §1): a slot is judged by its value at the start and at
///      the end of the transaction, so a clear and rewrite inside one transaction is never a
///      creation. Writes from reverted frames are ignored. Every Foundry test is one EVM
///      transaction, so "transaction" here means one top-level call made through `_ctx`.
///
///      Log lines (one per CREATE/CLEAR, one summary per transaction, one per scenario):
///        CENSUS|scenario|label|seq|payer|account name|account|slot|root|path|kind|day|level
///        CENSUSTX|scenario|label|seq|payer|ok|creates|clears|overwrites|unattributed|day|level
///        CENSUSMETA|scenario|startDay|endDay|startLevel|endLevel|txs|creates|clears|overwrites
///      `root` is the top-level slot (decimal) the slot hangs from, or the raw slot when the
///      walk failed. `path` lists the hops from the root outward, "/"-separated: `M<k>` is a
///      mapping element (k = word offset from the hashed element base, i.e. the struct member or
///      fixed-array word), `A<i>` a dynamic-array word i past keccak(length slot), `D` a plain
///      top-level slot, `U` an unattributed hashed slot.
abstract contract StorageCensus is DeployProtocol {
    uint256 internal constant MAX_MEMBER_OFFSET = 31;
    uint256 internal constant MAX_ARRAY_WORDS = 1 << 32;
    uint256 internal constant MAX_WIDE_OFFSET = 4096;
    uint256 internal constant DIRECT_SLOT_LIMIT = 1 << 64;

    string internal censusScenario;
    bool internal censusOn = true;
    uint256 internal censusSeq;
    uint256 internal censusCreates;
    uint256 internal censusClears;
    uint256 internal censusOverwrites;
    uint256 internal censusTxs;
    uint256 internal censusFailedTxs;
    uint24 internal censusStartDay;
    uint24 internal censusStartLevel;

    mapping(address => uint256) internal censusIndex; // index + 1 into censusNames
    string[] internal censusNames;

    /// @dev Keeper that cranks mineFlip and fulfils VRF in census scenarios (protocol-paid work).
    address internal constant CENSUS_KEEPER = address(0xC0FFEE0001);

    bytes4 internal constant SEL_NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant SEL_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    // ---------------------------------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------------------------------

    function _censusRegister(address a, string memory name) internal {
        if (a == address(0) || censusIndex[a] != 0) return;
        censusNames.push(name);
        censusIndex[a] = censusNames.length;
    }

    /// @dev Name every deployed contract. Game delegate modules write into the Game's storage;
    ///      they are named too in case one ever writes its own.
    function _censusRegisterProtocol() internal {
        _censusRegister(address(game), "Game");
        _censusRegister(address(coinflip), "Coinflip");
        _censusRegister(address(coin), "FLIP");
        _censusRegister(address(sdgnrs), "sDGNRS");
        _censusRegister(address(dgnrs), "DGNRS");
        _censusRegister(address(crapsBattle), "CRAPS");
        _censusRegister(address(jackpotBattle), "JackpotBattle");
        _censusRegister(address(crapsEngine), "CrapsEngine");
        _censusRegister(address(wwxrp), "WWXRP");
        _censusRegister(address(gnrus), "GNRUS");
        _censusRegister(address(affiliate), "Affiliate");
        _censusRegister(address(jackpots), "Jackpots");
        _censusRegister(address(vault), "Vault");
        _censusRegister(address(quests), "Quests");
        _censusRegister(address(afkingSubToken), "AFKingToken");
        _censusRegister(address(deityPass), "DeityPass");
        _censusRegister(address(parimutuel), "Parimutuel");
        _censusRegister(address(recordBounty), "RecordBounty");
        _censusRegister(address(ownerGovernance), "OwnerGovernance");
        _censusRegister(address(admin), "Admin");
        _censusRegister(address(icons32), "Icons32");
        _censusRegister(address(mockStETH), "MockStETH");
        _censusRegister(address(mockVRF), "MockVRF");
        _censusRegister(address(mockLINK), "MockLINK");
        _censusRegister(address(mockFeed), "MockFeed");
        _censusRegister(address(mintModule), "mod:Mint");
        _censusRegister(address(ticketModule), "mod:Ticket");
        _censusRegister(address(minerModule), "mod:Miner");
        _censusRegister(address(rngModule), "mod:Rng");
        _censusRegister(address(jackpotDrawModule), "mod:JackpotDraw");
        _censusRegister(address(degenesisModule), "mod:Degenesis");
        _censusRegister(address(advanceModule), "mod:Advance");
        _censusRegister(address(whaleModule), "mod:Whale");
        _censusRegister(address(jackpotModule), "mod:Jackpot");
        _censusRegister(address(decimatorModule), "mod:Decimator");
        _censusRegister(address(gameOverModule), "mod:GameOver");
        _censusRegister(address(lootboxModule), "mod:Lootbox");
        _censusRegister(address(boonModule), "mod:Boon");
        _censusRegister(address(degeneretteModule), "mod:Degenerette");
        _censusRegister(address(bingoModule), "mod:Bingo");
        _censusRegister(address(afkingModule), "mod:Afking");
        _censusRegister(address(foilModule), "mod:Foil");
    }

    function _censusBegin(string memory scenario) internal {
        if (censusNames.length == 0) _censusRegisterProtocol();
        censusScenario = scenario;
        censusStartDay = _censusDay();
        censusStartLevel = _censusLevel();
        censusCreates = 0;
        censusClears = 0;
        censusOverwrites = 0;
        censusTxs = 0;
        censusFailedTxs = 0;
    }

    function _censusEnd() internal {
        console.log(string.concat(
            "CENSUSMETA|", censusScenario, "|", vm.toString(uint256(censusStartDay)), "|",
            vm.toString(uint256(_censusDay())), "|", vm.toString(uint256(censusStartLevel)), "|",
            vm.toString(uint256(_censusLevel())), "|", vm.toString(censusTxs), "|",
            vm.toString(censusCreates), "|", vm.toString(censusClears), "|", vm.toString(censusOverwrites)
        ));
    }

    function _censusDay() internal view returns (uint24 d) {
        try game.currentDayView() returns (uint24 v) { d = v; } catch {}
    }

    function _censusLevel() internal view returns (uint24 l) {
        try game.level() returns (uint24 v) { l = v; } catch {}
    }

    // ---------------------------------------------------------------------------------------
    // One census transaction
    // ---------------------------------------------------------------------------------------

    /// @notice Make one top-level call as `from` and census its storage writes.
    /// @param protocolPaid true for mineFlip / keeper / VRF work, false for player actions.
    function _ctx(string memory label, bool protocolPaid, address from, address to, uint256 value, bytes memory data)
        internal
        returns (bool ok, bytes memory ret)
    {
        if (!censusOn) {
            vm.prank(from, from);
            (ok, ret) = to.call{value: value}(data);
            return (ok, ret);
        }
        uint256 seq = ++censusSeq;
        vm.startMappingRecording();
        vm.startStateDiffRecording();
        vm.prank(from, from);
        (ok, ret) = to.call{value: value}(data);
        // Collect in a fresh call frame: the decoded diff is large and memory never shrinks
        // inside one frame, so collecting here would grow the test frame without bound.
        this.censusCollect(label, protocolPaid, seq, ok);
        if (!ok) {
            bytes4 sel;
            if (ret.length >= 4) sel = bytes4(ret);
            console.log(string.concat("CENSUSREV|", censusScenario, "|", label, "|", vm.toString(seq), "|",
                vm.toString(abi.encodePacked(sel)), "|", vm.toString(ret.length)));
        }
    }

    /// @dev Per-transaction write table (open addressing over parallel arrays).
    struct Table {
        uint256 cap;
        address[] account;
        bytes32[] slot;
        bytes32[] prev;
        bytes32[] last;
        uint256[] order; // occupied indices, first-write order
        uint256 distinct;
        address[] baseAccount; // hashed mapping-element bases seen among this tx's writes
        bytes32[] base;
        uint256 bases;
    }

    /// @dev Only callable by this test. Stops both recordings.
    function censusCollect(string calldata label, bool protocolPaid, uint256 seq, bool ok) external {
        require(msg.sender == address(this), "census: self only");
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();

        // Count kept writes: tracked account, not reverted in its own or any parent frame.
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].reverted) continue;
            Vm.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                if (sa[j].isWrite && !sa[j].reverted && censusIndex[sa[j].account] != 0) ++n;
            }
        }
        Table memory t;
        t.cap = 16;
        while (t.cap < 2 * n + 1) t.cap <<= 1;
        t.account = new address[](t.cap);
        t.slot = new bytes32[](t.cap);
        t.prev = new bytes32[](t.cap);
        t.last = new bytes32[](t.cap);
        t.order = new uint256[](n);
        // Chronological: AccountAccess entries (with Resume entries) and their storage accesses are
        // in execution order, so the first kept write carries the tx-start value.
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].reverted) continue;
            Vm.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                Vm.StorageAccess memory s = sa[j];
                if (!s.isWrite || s.reverted || censusIndex[s.account] == 0) continue;
                uint256 h = uint256(keccak256(abi.encode(s.account, s.slot))) & (t.cap - 1);
                while (t.account[h] != address(0) && (t.account[h] != s.account || t.slot[h] != s.slot)) {
                    h = (h + 1) & (t.cap - 1);
                }
                if (t.account[h] == address(0)) {
                    t.account[h] = s.account;
                    t.slot[h] = s.slot;
                    t.prev[h] = s.previousValue;
                    t.order[t.distinct++] = h;
                }
                t.last[h] = s.newValue;
            }
        }

        _censusDiscoverBases(t);

        uint24 day = _censusDay();
        uint24 lvl = _censusLevel();
        string memory head = string.concat(
            "CENSUS|", censusScenario, "|", label, "|", vm.toString(seq), "|", protocolPaid ? "protocol" : "player", "|"
        );
        string memory tail = string.concat("|", vm.toString(uint256(day)), "|", vm.toString(uint256(lvl)));
        uint256[4] memory counts; // creates, clears, overwrites, unattributed
        for (uint256 d; d < t.distinct; ++d) {
            uint256 h = t.order[d];
            if (t.prev[h] == t.last[h]) continue;
            string memory kind;
            if (t.prev[h] == bytes32(0)) {
                kind = "CREATE";
                ++counts[0];
            } else if (t.last[h] == bytes32(0)) {
                kind = "CLEAR";
                ++counts[1];
            } else {
                ++counts[2];
                continue;
            }
            (bytes32 root, string memory path, bool attributed) = _censusAttribute(t.account[h], t.slot[h], t, acc);
            if (!attributed) ++counts[3];
            console.log(string.concat(
                head, censusNames[censusIndex[t.account[h]] - 1], "|", vm.toString(t.account[h]), "|",
                vm.toString(t.slot[h]), "|",
                uint256(root) < DIRECT_SLOT_LIMIT ? vm.toString(uint256(root)) : vm.toString(root), "|", path, "|", kind,
                tail
            ));
        }
        console.log(string.concat(
            "CENSUSTX|", censusScenario, "|", label, "|", vm.toString(seq), "|", protocolPaid ? "protocol" : "player", "|",
            ok ? "ok" : "reverted", "|", vm.toString(counts[0]), "|", vm.toString(counts[1]), "|",
            string.concat(vm.toString(counts[2]), "|", vm.toString(counts[3]), tail)
        ));
        censusCreates += counts[0];
        censusClears += counts[1];
        censusOverwrites += counts[2];
        ++censusTxs;
        if (!ok) ++censusFailedTxs;
        vm.stopMappingRecording();
    }

    /// @dev Walk a written slot up to its root: mapping hops through the recorded 64-byte keccak
    ///      preimages (trying member offsets 0..31 below the slot), dynamic-array hops through
    ///      keccak(slot) of a slot this tx wrote or read (a push writes the length, an indexed
    ///      write reads it for the bounds check), then keccak(p) of direct roots through the trait buffers.
    function _censusAttribute(address account, bytes32 slot, Table memory t, Vm.AccountAccess[] memory acc)
        internal
        view
        returns (bytes32 root, string memory path, bool attributed)
    {
        bytes32 cur = slot;
        if (uint256(cur) < DIRECT_SLOT_LIMIT) return (cur, "D", true);
        for (uint256 depth; depth < 12; ++depth) {
            if (uint256(cur) < DIRECT_SLOT_LIMIT) return (cur, path, true);
            bool hopped;
            for (uint256 k; k <= MAX_MEMBER_OFFSET; ++k) {
                (bool found,, bytes32 parent) = vm.getMappingKeyAndParentOf(account, bytes32(uint256(cur) - k));
                if (found) {
                    path = _censusPrepend(string.concat("M", vm.toString(k)), path);
                    cur = parent;
                    hopped = true;
                    break;
                }
            }
            if (hopped) continue;
            // Wide mapping values (e.g. uint256[256]): a base found from another write of this tx.
            for (uint256 b; b < t.bases; ++b) {
                if (t.baseAccount[b] != account || uint256(cur) < uint256(t.base[b])) continue;
                uint256 k = uint256(cur) - uint256(t.base[b]);
                if (k >= MAX_WIDE_OFFSET) continue;
                (,, bytes32 parent) = vm.getMappingKeyAndParentOf(account, t.base[b]);
                path = _censusPrepend(string.concat("M", vm.toString(k)), path);
                cur = parent;
                hopped = true;
                break;
            }
            if (hopped) continue;
            bytes32 lengthSlot;
            (hopped, lengthSlot) = _censusArrayBase(account, cur, t, acc);
            if (!hopped) break;
            path = _censusPrepend(string.concat("A", vm.toString(uint256(cur) - uint256(keccak256(abi.encode(lengthSlot))))), path);
            cur = lengthSlot;
        }
        if (uint256(cur) < DIRECT_SLOT_LIMIT) return (cur, path, true);
        return (cur, _censusPrepend("U", path), false);
    }

    /// @dev Record the hashed element base of every written slot found within 31 words of one.
    function _censusDiscoverBases(Table memory t) internal view {
        t.baseAccount = new address[](t.distinct);
        t.base = new bytes32[](t.distinct);
        for (uint256 d; d < t.distinct; ++d) {
            uint256 h = t.order[d];
            uint256 s = uint256(t.slot[h]);
            if (s < DIRECT_SLOT_LIMIT) continue;
            for (uint256 k; k <= MAX_MEMBER_OFFSET; ++k) {
                (bool found,,) = vm.getMappingKeyAndParentOf(t.account[h], bytes32(s - k));
                if (!found) continue;
                bytes32 b = bytes32(s - k);
                bool known;
                for (uint256 i = t.bases; i > 0 && i + 8 > t.bases; --i) {
                    if (t.base[i - 1] == b && t.baseAccount[i - 1] == t.account[h]) {
                        known = true;
                        break;
                    }
                }
                if (!known) {
                    t.baseAccount[t.bases] = t.account[h];
                    t.base[t.bases++] = b;
                }
                break;
            }
        }
    }

    function _censusArrayBase(address account, bytes32 cur, Table memory t, Vm.AccountAccess[] memory acc)
        internal
        pure
        returns (bool, bytes32)
    {
        for (uint256 d; d < t.distinct; ++d) {
            uint256 h = t.order[d];
            if (t.account[h] == account && _censusWithin(cur, t.slot[h])) return (true, t.slot[h]);
        }
        for (uint256 i; i < acc.length; ++i) {
            Vm.StorageAccess[] memory sa = acc[i].storageAccesses;
            for (uint256 j; j < sa.length; ++j) {
                if (sa[j].account == account && !sa[j].isWrite && _censusWithin(cur, sa[j].slot)) return (true, sa[j].slot);
            }
        }
        uint256 directLimit = GameSlots.LVL_TRAIT_ENTRY + 512;
        if (directLimit < 512) directLimit = 512;
        for (uint256 p; p < directLimit; ++p) {
            if (_censusWithin(cur, bytes32(p))) return (true, bytes32(p));
        }
        return (false, bytes32(0));
    }

    function _censusWithin(bytes32 cur, bytes32 lengthSlot) private pure returns (bool) {
        uint256 base = uint256(keccak256(abi.encode(lengthSlot)));
        return uint256(cur) >= base && uint256(cur) - base < MAX_ARRAY_WORDS;
    }

    function _censusPrepend(string memory hop, string memory path) private pure returns (string memory) {
        return bytes(path).length == 0 ? hop : string.concat(hop, "/", path);
    }

    // ---------------------------------------------------------------------------------------
    // Protocol-paid drivers
    // ---------------------------------------------------------------------------------------

    /// @dev Fulfil the latest VRF request if it is pending. Returns true when it fulfilled one.
    function _cFulfill(uint256 salt) internal returns (bool) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(req);
        if (fulfilled) return false;
        uint256 word = uint256(keccak256(abi.encode("census-vrf", req, salt)));
        // Bit 0 decides the daily coinflip and the BAF fire gate; boundary campaigns may pin it.
        if (censusWordParity == 1) word |= 1;
        else if (censusWordParity == 2) word = (word & ~uint256(1)) | 2;
        (bool ok,) = _ctx("vrfFulfill", true, CENSUS_KEEPER, address(mockVRF), 0,
            abi.encodeCall(mockVRF.fulfillRandomWords, (req, word)));
        return ok;
    }

    /// @dev One mineFlip crank. Returns 0 on success, 1 on NoWork, 2 on RngNotReady, 3 on any other revert.
    function _cMine() internal returns (uint8) {
        (bool ok, bytes memory ret) = _ctx("mineFlip", true, CENSUS_KEEPER, address(game), 0,
            abi.encodeCall(game.mineFlip, (uint32(0))));
        if (ok) return 0;
        if (ret.length == 4 && bytes4(ret) == SEL_NO_WORK) return 1;
        if (ret.length == 4 && bytes4(ret) == SEL_RNG_NOT_READY) return 2;
        return 3;
    }

    /// @dev Crank mineFlip until it reports no work, fulfilling VRF requests as they appear.
    /// @return calls successful cranks.
    function _cMineAll(uint256 maxCalls, uint256 salt) internal returns (uint256 calls) {
        for (uint256 i; i < maxCalls; ++i) {
            _cFulfill(salt + i);
            uint8 action = game.nextMinerAction();
            if (action == 0) return calls; // Idle
            if (action == 2) {
                // Wait: a word is outstanding; answer it or stop.
                if (!_cFulfill(salt + i + 7)) return calls;
                continue;
            }
            uint8 r = _cMine();
            if (r == 0) {
                ++calls;
                continue;
            }
            if (r == 3) {
                ++censusMineReverts;
                return calls;
            }
            if (!_cFulfill(salt + i + 7)) return calls;
        }
    }

    uint256 internal censusMineReverts;
    /// @dev 0 = free VRF words, 1 = force odd (flip wins, BAF fires), 2 = force even.
    uint8 internal censusWordParity;
}
