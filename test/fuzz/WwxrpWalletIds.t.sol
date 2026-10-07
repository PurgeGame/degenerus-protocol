// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title WwxrpWalletIds -- WWXRP draw and incinerator keyed by wallet ID on the real protocol
/// @notice `enter` takes the entrant's ID from the activity read and registers a first-time entrant
///         (the burn pays) before anything keys on it; the daily entry word is `cum | id << 96`,
///         the bucket hashes the ID, the WWXRP boon lane is read raw at
///         `keccak(id, GAME_BOON_PACKED_SLOT) + 1` and consumed by ID; a claim by anyone credits
///         the stored ID; the incinerator entry is one slot `cum | id << 192` and resolve returns
///         and credits the winner's ID; `consumeBoon(address)` resolves the ID with walletIdOf.
contract WwxrpWalletIdsTest is DeployProtocol {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant DRAW_ENTERED =
        keccak256("DrawEntered(uint24,address,uint8,uint32,uint256,uint256,uint256)");
    bytes32 private constant DRAW_CLAIMED = keccak256("DrawClaimed(uint24,uint32,bool,uint256,uint8,uint32)");
    bytes32 private constant INCIN_RESOLVED = keccak256("IncineratorResolved(uint24,uint32,uint256,uint256,uint256)");

    bytes32 private constant DOM_BUCKET = "WWXRP_DRAW_BUCKET";
    bytes32 private constant DOM_BIG = "WWXRP_DRAW_BIG";
    bytes32 private constant DOM_SMALL = "WWXRP_DRAW_SMALL";
    bytes32 private constant DOM_WIN_BUCKET = "WWXRP_DRAW_WIN_BUCKET";
    bytes32 private constant DOM_INCIN_WINNER = "WWXRP_INCIN_WINNER";

    /// @dev WWXRP storage roots (scripts/layout/golden/WWXRP.json).
    uint256 private constant DRAW_ENTRY_ROOT = 4;
    uint256 private constant INCIN_ENTRY_ROOT = 7;
    uint256 private constant WWXRP_LANE_SHIFT = 232;

    function setUp() public {
        _deployProtocol();
    }

    // =====================================================================
    //                              helpers
    // =====================================================================

    function _today() internal view returns (uint24) {
        return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }

    function _fund(address p, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(p, amount);
    }

    function _enter(address p, uint256 amount) internal {
        _fund(p, amount);
        vm.prank(p);
        wwxrp.enter(amount);
    }

    function _gameId(address p) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), GameSlotKeys.mintPacked(p))) >> 224);
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _bucketRef(uint24 day, uint32 id) internal view returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(DOM_BUCKET, block.chainid, address(wwxrp), day, id))) % 10);
    }

    function _drawEntrySlot(uint24 day, uint8 bucket, uint32 index) internal pure returns (bytes32) {
        uint256 key = (uint256(day % 3) << 40) | (uint256(bucket) << 32) | index;
        return keccak256(abi.encode(key, DRAW_ENTRY_ROOT));
    }

    function _incinSlot(uint24 bracket, uint32 index) internal pure returns (bytes32) {
        return keccak256(abi.encode((uint256(bracket) << 32) | index, INCIN_ENTRY_ROOT));
    }

    /// @dev `boonPacked[id].slot1` (the lane word WWXRP reads raw).
    function _boonSlot1(uint32 id) internal pure returns (bytes32) {
        return bytes32(uint256(GameSlotKeys.byId(id, GameSlots.BOON_PACKED)) + 1);
    }

    /// @dev A live, non-deity WWXRP lane of `tier` stamped today for wallet `id`.
    function _seedWwxrpLane(uint32 id, uint256 tier) internal {
        bytes32 s = _boonSlot1(id);
        uint256 v = uint256(vm.load(address(game), s));
        uint256 lane = tier | (uint256(game.currentDayView()) << 3);
        vm.store(address(game), s, bytes32((v & ~(uint256(0xFFFFFF) << WWXRP_LANE_SHIFT)) | (lane << WWXRP_LANE_SHIFT)));
    }

    function _h(bytes32 dom, uint24 day, uint256 word) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(dom, address(wwxrp), day, word)));
    }

    /// @dev A next-day word whose SMALL gate hits (BIG misses) in `bucket` for participation `day`.
    function _smallWordFor(uint24 day, uint8 bucket) internal view returns (uint256 w) {
        for (w = uint256(keccak256(abi.encode("wwxrp_wallet_ids", day, bucket)));; ++w) {
            if (_h(DOM_BIG, day, w) % 365 == 0) continue;
            if (_h(DOM_SMALL, day, w) % 30 != 0) continue;
            if (_h(DOM_WIN_BUCKET, day, w) % 10 == bucket) return w;
        }
    }

    function _registrations(Vm.Log[] memory logs) internal view returns (uint256 n, uint32 lastId, address lastOwner) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != WALLET_REGISTERED) continue;
            ++n;
            lastId = uint32(uint256(logs[i].topics[1]));
            lastOwner = address(uint160(uint256(logs[i].topics[2])));
        }
    }

    /// @dev The effective score `player`'s last DrawEntered in `logs` recorded.
    function _effectiveOf(Vm.Log[] memory logs, address player) internal view returns (uint256 effective) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != DRAW_ENTERED) continue;
            if (address(uint160(uint256(logs[i].topics[2]))) != player) continue;
            (,,, effective,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256));
        }
    }

    // =====================================================================
    //                               entry
    // =====================================================================

    /// @notice A first-time entrant registers exactly once; the entry word, the bucket and the
    ///         event's bucket are keyed by that ID; a second entry needs no registration.
    function test_FirstEnter_RegistersOnce_EntryAndBucketKeyedById() public {
        address p = makeAddr("first_entrant");
        _fund(p, 1_000);
        uint32 expectedId = uint32(_walletCount());
        uint24 day = _today();

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.registerWallet, (p, true)), 1);
        vm.recordLogs();
        vm.prank(p);
        wwxrp.enter(100);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 n, uint32 rid, address owner) = _registrations(logs);
        assertEq(n, 1, "exactly one WalletRegistered");
        assertEq(rid, expectedId);
        assertEq(owner, p);
        assertEq(_gameId(p), expectedId);

        uint8 bucket = wwxrp.bucketOf(day, expectedId);
        assertEq(bucket, _bucketRef(day, expectedId), "bucket hashes the wallet ID");
        assertEq(wwxrp.bucketOf(day, 0), 10, "ID 0 has no bucket");
        (uint32 eid, uint256 cum) = wwxrp.entryAt(day, bucket, 0);
        assertEq(eid, expectedId);
        assertGt(cum, 0);
        assertEq(
            uint256(vm.load(address(wwxrp), _drawEntrySlot(day, bucket, 0))),
            cum | (uint256(expectedId) << 96),
            "entry word = cum | id << 96"
        );
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != DRAW_ENTERED) continue;
            assertEq(address(uint160(uint256(logs[i].topics[2]))), p, "DrawEntered keeps the entrant address");
            (uint8 evBucket,,,,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256));
            assertEq(evBucket, bucket);
            seen = true;
        }
        assertTrue(seen);

        vm.prank(p);
        wwxrp.enter(100);
        (eid,) = wwxrp.entryAt(day, bucket, 1);
        assertEq(eid, expectedId, "same bucket, same ID; no second registration");
    }

    /// @notice The public bucket view matches the documented preimage for every nonzero ID and
    ///         returns BUCKET_COUNT (no bucket) for ID 0.
    function testFuzz_BucketOf_MatchesIdPreimage(uint24 day, uint32 id) public view {
        uint8 b = wwxrp.bucketOf(day, id);
        if (id == 0) {
            assertEq(b, 10);
        } else {
            assertEq(b, _bucketRef(day, id));
            assertLt(b, 10);
        }
    }

    /// @notice Past PAID_ADMISSION_WALLETS a new entrant's burn reverts; a registered one enters.
    function test_PastPaidAdmission_NewEntrantReverts_ExistingEnters() public {
        address e = makeAddr("adm_existing_entrant");
        address n = makeAddr("adm_new_entrant");
        uint32 eid = _giveWalletId(e);
        _fund(e, 1_000);
        _fund(n, 1_000);
        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(uint256(3_000_000_001)));
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(n);
        wwxrp.enter(100);
        assertEq(wwxrp.balanceOf(n), 1_000);
        uint24 day = _today();
        vm.prank(e);
        wwxrp.enter(100);
        (uint32 got,) = wwxrp.entryAt(day, wwxrp.bucketOf(day, eid), 0);
        assertEq(got, eid);
    }

    // =====================================================================
    //                               boons
    // =====================================================================

    /// @notice The raw reader's key equals `boonPacked(id).slot1`; `enter` consumes the lane of
    ///         the entrant's ID (and only when that lane holds a tier) and the boost lands in the
    ///         entry weight.
    function test_BoonLane_ReadRawById_ConsumedById() public {
        address p = makeAddr("boon_holder");
        address q = makeAddr("boon_none");
        uint32 pid = _giveWalletId(p);
        uint32 qid = _giveWalletId(q);
        _seedWwxrpLane(pid, 1);
        (, uint256 slot1) = game.boonPacked(pid);
        assertEq(uint256(vm.load(address(game), _boonSlot1(pid))), slot1, "raw key = boonPacked(id).slot1");
        assertEq((slot1 >> WWXRP_LANE_SHIFT) & 3, 1);

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (pid)), 1);
        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (qid)), 0);
        vm.expectCall(address(game), abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        (uint256 pScore,) = game.playerActivityScore(p);
        (uint256 qScore,) = game.playerActivityScore(q);
        vm.recordLogs();
        _enter(p, 1_000);
        _enter(q, 1_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_effectiveOf(logs, p), (1_000 * wwxrp.drawMultBps(pScore) * 10_400) / 1e8, "tier-1 boost (+4%)");
        assertEq(_effectiveOf(logs, q), (1_000 * wwxrp.drawMultBps(qScore) * 10_000) / 1e8, "no boost");
        (, slot1) = game.boonPacked(pid);
        assertEq((slot1 >> WWXRP_LANE_SHIFT) & 3, 0, "the ID's lane is spent");
    }

    /// @notice A trusted minter's `consumeBoon(address)` resolves the ID with walletIdOf: an ID-less
    ///         address consumes ID 0 (nothing) and is not registered; a registered one spends its lane.
    function test_ConsumeBoon_ResolvesByWalletIdOf() public {
        address owner = makeAddr("vault_owner");
        address app = makeAddr("trusted_app");
        vm.mockCall(address(vault), abi.encodeWithSignature("isVaultOwner(address)", owner), abi.encode(true));
        vm.prank(owner);
        wwxrp.setTrustedMinter(app, true);

        address x = makeAddr("boon_idless");
        address p = makeAddr("boon_registered");
        uint32 pid = _giveWalletId(p);
        _seedWwxrpLane(pid, 2);

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (uint32(0))), 1);
        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (pid)), 1);
        vm.prank(app);
        assertEq(wwxrp.consumeBoon(x), 0);
        vm.prank(app);
        assertEq(wwxrp.consumeBoon(p), 800, "tier 2 x 400 bps");
        (, uint256 slot1) = game.boonPacked(pid);
        assertEq((slot1 >> WWXRP_LANE_SHIFT) & 3, 0);
        assertEq(_gameId(x), 0, "a lookup never registers");

        vm.expectRevert(WWXRP.OnlyMinter.selector);
        vm.prank(x);
        wwxrp.consumeBoon(p);
    }

    // =====================================================================
    //                               claim
    // =====================================================================

    /// @notice Anyone can run `claim`; the prize is credited to the ID stored in the winning entry
    ///         (visible to the winner's address through walletIdOf) and the event carries the ID.
    function test_ClaimByAnyone_CreditsStoredId() public {
        address p = makeAddr("draw_winner");
        uint24 day = _today();
        _enter(p, 100);
        uint32 id = _gameId(p);
        uint8 bucket = wwxrp.bucketOf(day, id);
        RecyclingState.seedDailyWord(address(game), day + 1, _smallWordFor(day, bucket));
        vm.warp(block.timestamp + 1 days);

        (bool found, uint32 idx, uint32 wid) = wwxrp.findWinningEntry(day);
        assertTrue(found);
        assertEq(idx, 0);
        assertEq(wid, id, "winning entry view returns the ID");

        address runner = makeAddr("claim_runner");
        vm.expectCall(address(coinflip), abi.encodeCall(Coinflip.creditFlip, (id, 10_000)), 1);
        vm.recordLogs();
        vm.prank(runner);
        wwxrp.claim(day, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != DRAW_CLAIMED) continue;
            assertEq(uint24(uint256(logs[i].topics[1])), day);
            assertEq(uint32(uint256(logs[i].topics[2])), id, "DrawClaimed carries the winner ID");
            seen = true;
        }
        assertTrue(seen);
        assertTrue(wwxrp.dayClaimed(day));
        assertEq(coinflip.coinflipAmount(p), 10_000, "prize staked under the winner's ID");
        assertEq(coinflip.coinflipAmount(runner), 0);
        assertEq(_gameId(runner), 0);
    }

    // =====================================================================
    //                             incinerator
    // =====================================================================

    /// @notice An x99 burn writes ONE incinerator slot `cum | id << 192` (the next slot untouched);
    ///         resolve returns the reference winner's ID and credits it.
    function test_Incinerator_OneSlotEntry_ResolveReturnsAndCreditsId() public {
        vm.mockCall(address(game), abi.encodeWithSignature("level()"), abi.encode(uint24(199)));
        address p1 = makeAddr("incin_1");
        address p2 = makeAddr("incin_2");
        _fund(p1, 1_000);
        _fund(p2, 1_000);

        vm.record();
        vm.prank(p1);
        wwxrp.enter(100);
        (, bytes32[] memory writes) = vm.accesses(address(wwxrp));
        bytes32 s0 = _incinSlot(200, 0);
        uint256 hits;
        for (uint256 i; i < writes.length; ++i) {
            if (writes[i] == s0) ++hits;
            assertTrue(writes[i] != bytes32(uint256(s0) + 1), "the slot after the entry is never written");
        }
        assertEq(hits, 1, "one struct store");
        vm.prank(p2);
        wwxrp.enter(300);
        uint32 id1 = _gameId(p1);
        uint32 id2 = _gameId(p2);

        (uint32 e1, uint256 c1) = wwxrp.incineratorEntryAt(200, 0);
        (uint32 e2, uint256 c2) = wwxrp.incineratorEntryAt(200, 1);
        assertEq(e1, id1);
        assertEq(e2, id2);
        assertEq(uint256(vm.load(address(wwxrp), s0)), c1 | (uint256(id1) << 192), "entry = cum | id << 192");
        assertEq(uint256(vm.load(address(wwxrp), bytes32(uint256(s0) + 1))), 0);
        bytes32 s1 = _incinSlot(200, 1);
        assertEq(uint256(vm.load(address(wwxrp), s1)), c2 | (uint256(id2) << 192));
        assertEq(uint256(vm.load(address(wwxrp), bytes32(uint256(s1) + 1))), 0);

        uint24 armedDay = 7;
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(Coinflip.bafDrawInfo.selector),
            abi.encode(armedDay, uint96(1_000_000), uint32(3))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(Coinflip.getCoinflipDayResult.selector, armedDay),
            abi.encode(uint16(1), false)
        );
        uint256 word = uint256(keccak256("incinerator_word"));
        (uint256 total,) = wwxrp.incineratorInfo(200);
        assertEq(total, c2);
        uint256 roll = uint256(keccak256(abi.encodePacked(DOM_INCIN_WINNER, address(wwxrp), uint24(200), word))) % total;
        uint32 expected = c1 > roll ? id1 : id2;

        vm.expectCall(address(coinflip), abi.encodeCall(Coinflip.creditFlip, (expected, 100_000)), 1);
        vm.recordLogs();
        vm.prank(address(game));
        uint32 winner = wwxrp.resolveIncinerator(200, word);
        assertEq(winner, expected, "resolve returns the winner's ID");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(wwxrp) || logs[i].topics[0] != INCIN_RESOLVED) continue;
            assertEq(uint32(uint256(logs[i].topics[2])), expected, "IncineratorResolved carries the ID");
            (uint256 award,,) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            assertEq(award, 100_000);
            seen = true;
        }
        assertTrue(seen);
        assertEq(coinflip.coinflipAmount(expected == id1 ? p1 : p2), 100_000, "credited under the winner's ID");

        vm.prank(address(game));
        assertEq(wwxrp.resolveIncinerator(300, word), 0, "empty bracket");
    }
}
