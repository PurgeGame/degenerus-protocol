// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IDegenerusGameDecimatorModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @dev Etched over the Game to drive the decimator walk with a chosen budget, through the same
///      delegatecall mineFlip's `_decimatorSettle` makes.
contract DecimatorListWalkHarness is DegenerusGame {
    function settleDec(uint256 budgetUnits) external returns (uint256 settled, uint256 unitsUsed, bool moved) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameDecimatorModule.settleDecimatorWinners.selector, budgetUnits)
        );
        require(ok, "walk reverted");
        return abi.decode(data, (uint256, uint256, bool));
    }
}

/// @title DecimatorListRecord — the list entry is the burner's record, and mineFlip settles winners
/// @notice Pins the decimator storage model and its settle walk:
///           1. BURN    — a first burn in a window appends an entry (owner, weight, base) at the end of
///                        its subbucket list and points the player's pointer at it; later burns add to
///                        it in place; a better bucket empties the old position and re-appends the
///                        entry, carrying weight and base. Every subbucket total equals the sum of its
///                        entries, and every list length counts its appends.
///           2. ORDER   — mineFlip's decimator leg settles winning entries oldest level first,
///                        denominators 2..12, positions ascending, stepping over x95 and over levels
///                        whose draw paid no one, and waiting at a level whose draw is still to come.
///           3. CHUNKS  — a backlog settled across several full mineFlip calls ends in the same state
///                        as the same backlog walked one entry per call.
///           4. GATES   — the leg settles nothing while the RNG lock is up or the game is over.
///           5. ONCE    — the walk settles each winning entry exactly once, steps over an entry a
///                        migration emptied, and no entry point settles a chosen entry.
///           6. BOUNTY  — a settling call pays one MinerBounty of kind 5, pro-rated on the work knee.
contract DecimatorListRecord is DeployProtocol {
    // forge inspect DegenerusGame storageLayout
    uint256 internal constant SLOT_HEADER = 0; // level @ byte 12, rngLockedFlag @ 19, gameOver @ 21
    uint256 internal constant SLOT_POOLS_1 = 1; // claimablePool in the high 128 bits
    uint256 internal constant SLOT_DEC_ENTRY = 40; // mapping(uint256 => DecEntry)
    uint256 internal constant SLOT_DEC_SUB = 41; // mapping(uint24 => DecSubbucket[13][13])
    uint256 internal constant SLOT_DEC_ROUNDS = 42; // mapping(uint24 => DecClaimRound)
    uint256 internal constant SLOT_DEC_POINTER = 75; // mapping(address => DecPointer)
    uint256 internal constant SLOT_DEC_CURSOR = 76; // DecSettleCursor

    uint256 internal constant MULT_1X = 10_000;
    uint256 internal constant DEC_BASE_UNIT = 1e15;
    uint8 internal constant KIND_DECIMATOR = 5;
    uint256 internal constant OPEN_WEIGHT_BUDGET = 1920; // GameAfkingModule
    uint256 internal constant BOUNTY_ETH_TARGET = 885_000_000_000_000; // GameAfkingModule
    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;

    bytes32 internal constant DEC_CLAIMED_SIG =
        keccak256("DecimatorClaimed(address,uint24,uint256,uint256,uint256)");
    bytes32 internal constant MINER_BOUNTY_SIG = keccak256("MinerBounty(uint8,address,uint256)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 64;
    uint256 private _lastFulfilledReqId;

    address internal keeper;

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("dec_list_keeper");
        _settleGame(uint256(keccak256("dec-list-settle")));
        game.openBoxes(1_000);
        _quietCrapsTable();
    }

    // ---------------------------------------------------------------------
    //                               harness
    // ---------------------------------------------------------------------

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    function _burn(address player, uint24 lvl, uint8 bucket, uint256 base) internal returns (uint8) {
        vm.prank(ContractAddresses.COIN);
        return game.recordDecBurn(player, lvl, bucket, base, MULT_1X);
    }

    function _subOf(address player, uint24 lvl, uint8 bucket) internal pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(player, lvl, bucket))) % bucket);
    }

    function _winningSub(uint256 rngWord, uint8 denom) internal pure returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(rngWord, denom))) % denom);
    }

    /// @dev A fresh address whose subbucket for (lvl, bucket) is `sub` (or is not, when `want` is false).
    function _playerIn(string memory tag, uint256 i, uint24 lvl, uint8 bucket, uint8 sub, bool want)
        internal
        returns (address p)
    {
        for (uint256 n; ; ++n) {
            p = makeAddr(string(abi.encodePacked(tag, vm.toString(i), "-", vm.toString(n))));
            if ((_subOf(p, lvl, bucket) == sub) == want) return p;
        }
    }

    function _key(uint24 lvl, uint8 denom, uint8 sub, uint32 pos) internal pure returns (uint256) {
        return (uint256(lvl) << 48) | (uint256(denom) << 40) | (uint256(sub) << 32) | uint256(pos);
    }

    function _entry(uint24 lvl, uint8 denom, uint8 sub, uint32 pos)
        internal
        view
        returns (address owner, uint64 weightMilli, uint32 baseMilli)
    {
        uint256 w = uint256(
            vm.load(address(game), keccak256(abi.encode(_key(lvl, denom, sub, pos), SLOT_DEC_ENTRY)))
        );
        owner = address(uint160(w));
        weightMilli = uint64(w >> 160);
        baseMilli = uint32(w >> 224);
    }

    function _agg(uint24 lvl, uint8 denom, uint8 sub) internal view returns (uint256 total, uint32 len) {
        uint256 arrBase = uint256(keccak256(abi.encode(uint256(lvl), SLOT_DEC_SUB)));
        uint256 w = uint256(vm.load(address(game), bytes32(arrBase + uint256(denom) * 13 + sub)));
        total = uint192(w);
        len = uint32(w >> 192);
    }

    function _pointer(address player)
        internal
        view
        returns (uint24 lvl, uint8 bucket, uint8 sub, uint32 pos)
    {
        uint256 w = uint256(vm.load(address(game), keccak256(abi.encode(player, SLOT_DEC_POINTER))));
        lvl = uint24(w);
        bucket = uint8(w >> 24);
        sub = uint8(w >> 32);
        pos = uint32(w >> 40);
    }

    function _cursor() internal view returns (uint24 lvl, uint8 denom, uint32 pos) {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_DEC_CURSOR)));
        lvl = uint24(w);
        denom = uint8(w >> 24);
        pos = uint32(w >> 32);
    }

    function _roundPool(uint24 lvl) internal view returns (uint256) {
        return uint96(uint256(vm.load(address(game), keccak256(abi.encode(uint256(lvl), SLOT_DEC_ROUNDS)))));
    }

    /// @dev Run the real draw for `lvl`, then book the spend into claimablePool as the advance does.
    function _draw(uint24 lvl, uint256 poolWei, uint256 rngWord) internal {
        vm.prank(address(game));
        uint256 returned = game.runDecimatorJackpot(poolWei, lvl, rngWord);
        uint256 spend = poolWei - returned;
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_POOLS_1)));
        uint256 claimable = (w >> 128) + spend;
        w = (w & ((uint256(1) << 128) - 1)) | (claimable << 128);
        vm.store(address(game), bytes32(SLOT_POOLS_1), bytes32(w));
    }

    function _setHeaderByte(uint256 byteIdx, uint256 value) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        w = (w & ~(uint256(0xFF) << (byteIdx * 8))) | (value << (byteIdx * 8));
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(w));
    }

    function _setLevel(uint24 lvl) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        w = (w & ~(uint256(0xFFFFFF) << 96)) | (uint256(lvl) << 96);
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(w));
    }

    /// @dev Install `n` winners in each listed denominator at `lvl`, draw with `rngWord`, and return
    ///      them in walk order (denominator ascending, then position).
    function _installWinners(uint24 lvl, uint8[] memory denoms, uint256 n, uint256 rngWord, uint256 poolWei)
        internal
        returns (address[] memory winners)
    {
        winners = new address[](denoms.length * n);
        uint256 k;
        for (uint256 d; d < denoms.length; ++d) {
            uint8 denom = denoms[d];
            uint8 wsub = _winningSub(rngWord, denom);
            // A loser in the same denominator, so the winning total is not the whole level.
            _burn(_playerIn(string(abi.encodePacked("lose", vm.toString(lvl))), d, lvl, denom, wsub, false), lvl, denom, 2_000 ether);
            for (uint256 i; i < n; ++i) {
                address p = _playerIn(
                    string(abi.encodePacked("win", vm.toString(lvl), "-", vm.toString(denom), "-")), i, lvl, denom, wsub, true
                );
                _burn(p, lvl, denom, 1_000 ether + i * 7 ether);
                winners[k++] = p;
            }
        }
        _draw(lvl, poolWei, rngWord);
    }

    function _mine() internal {
        vm.prank(keeper);
        game.mineFlip();
    }

    function _claimedOrder(Vm.Log[] memory logs) internal pure returns (address[] memory out, uint256 n) {
        out = new address[](logs.length);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == DEC_CLAIMED_SIG) {
                out[n++] = address(uint160(uint256(logs[i].topics[1])));
            }
        }
    }

    function _bounty(Vm.Log[] memory logs) internal pure returns (uint256 count, uint8 kind, uint256 amount) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 2 && logs[i].topics[0] == MINER_BOUNTY_SIG) {
                ++count;
                (kind, amount) = abi.decode(logs[i].data, (uint8, uint256));
            }
        }
    }

    function _denoms(uint8 a) internal pure returns (uint8[] memory d) {
        d = new uint8[](1);
        d[0] = a;
    }

    function _denoms(uint8 a, uint8 b, uint8 c) internal pure returns (uint8[] memory d) {
        d = new uint8[](3);
        d[0] = a;
        d[1] = b;
        d[2] = c;
    }

    // ---------------------------------------------------------------------
    //                               1. BURN
    // ---------------------------------------------------------------------

    function test_FirstBurnAppendsEntryAndPointsAtIt() public {
        uint24 lvl = 5;
        address a = _playerIn("a", 0, lvl, 7, 3, true);
        address b = _playerIn("b", 0, lvl, 7, 3, true);

        assertEq(_burn(a, lvl, 7, 1_500 ether), 7, "bucket used");
        _burn(b, lvl, 7, 2_000 ether);

        (uint24 pl, uint8 pb, uint8 ps, uint32 pp) = _pointer(a);
        assertEq(pl, lvl);
        assertEq(pb, 7);
        assertEq(ps, 3);
        assertEq(pp, 0, "a first");
        (, , , pp) = _pointer(b);
        assertEq(pp, 1, "b appended after a");

        (address owner, uint64 w, uint32 base) = _entry(lvl, 7, 3, 0);
        assertEq(owner, a);
        assertEq(w, 1_500_000, "1x weight in milli-FLIP");
        assertEq(base, 1_500_000, "base in milli-FLIP");

        (uint256 total, uint32 len) = _agg(lvl, 7, 3);
        assertEq(len, 2);
        assertEq(total, 3_500 ether, "total = sum of entry weights, wei");
    }

    function test_RepeatBurnAddsInPlace() public {
        uint24 lvl = 5;
        address a = _playerIn("a", 0, lvl, 6, 1, true);
        _burn(a, lvl, 6, 1_000 ether);
        _burn(a, lvl, 6, 4_000 ether);

        (, , , uint32 pp) = _pointer(a);
        assertEq(pp, 0);
        (, uint64 w, uint32 base) = _entry(lvl, 6, 1, 0);
        assertEq(w, 5_000_000);
        assertEq(base, 5_000_000);
        (uint256 total, uint32 len) = _agg(lvl, 6, 1);
        assertEq(len, 1, "no second entry");
        assertEq(total, 5_000 ether);
    }

    function test_BetterBucketMovesTheEntry() public {
        uint24 lvl = 5;
        address a = makeAddr("migrant");
        uint8 fromSub = _subOf(a, lvl, 9);
        uint8 toSub = _subOf(a, lvl, 5);
        // Someone already sits in the destination list, so the migrant lands at position 1.
        _burn(_playerIn("occupant", 0, lvl, 5, toSub, true), lvl, 5, 1_000 ether);

        _burn(a, lvl, 9, 3_000 ether);
        vm.recordLogs();
        assertEq(_burn(a, lvl, 5, 1_000 ether), 5, "strictly better bucket taken");

        (address oldOwner, uint64 oldW, ) = _entry(lvl, 9, fromSub, 0);
        assertEq(oldOwner, address(0), "old position emptied");
        assertEq(oldW, 0);
        (uint256 oldTotal, uint32 oldLen) = _agg(lvl, 9, fromSub);
        assertEq(oldTotal, 0, "weight left the old aggregate");
        assertEq(oldLen, 1, "old list keeps its length");

        (uint24 pl, uint8 pb, uint8 ps, uint32 pp) = _pointer(a);
        assertEq(pl, lvl);
        assertEq(pb, 5);
        assertEq(ps, toSub);
        assertEq(pp, 1);
        (address owner, uint64 w, uint32 base) = _entry(lvl, 5, toSub, 1);
        assertEq(owner, a);
        assertEq(w, 4_000_000, "carried 3000 + fresh 1000");
        assertEq(base, 4_000_000, "base carried");
        (uint256 total, uint32 len) = _agg(lvl, 5, toSub);
        assertEq(len, 2);
        assertEq(total, 5_000 ether);

        // A worse bucket later is ignored: the entry stays put.
        _burn(a, lvl, 8, 1_000 ether);
        (, pb, , pp) = _pointer(a);
        assertEq(pb, 5);
        assertEq(pp, 1);
    }

    function test_NextWindowReusesThePointer() public {
        address a = makeAddr("two-windows");
        _burn(a, 5, 6, 1_000 ether);
        _burn(a, 15, 6, 2_000 ether);
        (uint24 pl, , , uint32 pp) = _pointer(a);
        assertEq(pl, 15, "pointer moved to the new window");
        assertEq(pp, 0);
        (address owner, uint64 w, ) = _entry(5, 6, _subOf(a, 5, 6), 0);
        assertEq(owner, a, "level-5 record kept");
        assertEq(w, 1_000_000);
        // A fresh window starts its base from zero: the multiplier cap measures one level.
        (, , uint32 base) = _entry(15, 6, _subOf(a, 15, 6), 0);
        assertEq(base, 2_000_000);
    }

    /// @notice Every subbucket total equals the sum of its live entries, and every length counts its
    ///         appends, across random burns and migrations by a small crowd.
    function testFuzz_TotalsEqualSumOfEntries(uint256 seed) public {
        uint24 lvl = 5;
        address[4] memory crowd =
            [makeAddr("c0"), makeAddr("c1"), makeAddr("c2"), makeAddr("c3")];
        for (uint256 i; i < 24; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            address p = crowd[r % 4];
            uint8 bucket = uint8(5 + ((r >> 8) % 8));
            _burn(p, lvl, bucket, 1_000 ether + ((r >> 16) % 50_000) * 1 ether);
        }
        for (uint8 denom = 5; denom <= 12; ++denom) {
            for (uint8 sub; sub < denom; ++sub) {
                (uint256 total, uint32 len) = _agg(lvl, denom, sub);
                uint256 sum;
                for (uint32 pos; pos < len; ++pos) {
                    (, uint64 w, ) = _entry(lvl, denom, sub, pos);
                    sum += uint256(w) * DEC_BASE_UNIT;
                }
                assertEq(total, sum, "total == sum of entries");
                (address past, , ) = _entry(lvl, denom, sub, len);
                assertEq(past, address(0), "nothing past the end");
            }
        }
        // Each crowd member holds exactly one live entry: the one its pointer names.
        for (uint256 c; c < 4; ++c) {
            (uint24 pl, uint8 pb, uint8 ps, uint32 pp) = _pointer(crowd[c]);
            if (pl == 0) continue;
            (address owner, uint64 w, ) = _entry(lvl, pb, ps, pp);
            assertEq(owner, crowd[c]);
            assertGt(w, 0);
        }
    }

    // ---------------------------------------------------------------------
    //                               2. ORDER
    // ---------------------------------------------------------------------

    function test_MineFlipSettlesWinnersInListOrder() public {
        uint256 rngWord = uint256(keccak256("order"));
        address[] memory winners = _installWinners(5, _denoms(12, 5, 8), 3, rngWord, 3 ether);

        uint256[] memory before = new uint256[](winners.length);
        for (uint256 i; i < winners.length; ++i) before[i] = game.claimableWinningsOf(winners[i]);

        vm.recordLogs();
        _mine();
        (address[] memory order, uint256 n) = _claimedOrder(vm.getRecordedLogs());

        assertEq(n, 9, "every winner settled in one call");
        // Walk order: denominator 5, then 8, then 12 — each in position order.
        address[9] memory expect = [
            winners[3], winners[4], winners[5], // denom 5
            winners[6], winners[7], winners[8], // denom 8
            winners[0], winners[1], winners[2] // denom 12
        ];
        for (uint256 i; i < 9; ++i) assertEq(order[i], expect[i], "list order");
        for (uint256 i; i < winners.length; ++i) {
            assertGt(game.claimableWinningsOf(winners[i]), before[i], "winner credited");
        }
        (uint24 cl, uint8 cd, uint32 cp) = _cursor();
        assertEq(cl, 15, "cursor moved past the finished level");
        assertEq(cd, 2);
        assertEq(cp, 0);
    }

    function test_WalkStepsOverX95AndEmptyDrawsAndWaitsAtUndrawnLevel() public {
        uint256 rngWord = uint256(keccak256("x00"));
        address[] memory a = _installWinners(85, _denoms(6), 2, rngWord, 1 ether);
        address[] memory b = _installWinners(100, _denoms(2), 2, rngWord ^ 1, 1 ether);
        _setLevel(101);
        assertEq(_roundPool(95), 0, "x95 never draws");

        vm.recordLogs();
        _mine();
        (address[] memory order, uint256 n) = _claimedOrder(vm.getRecordedLogs());
        assertEq(n, 4);
        assertEq(order[0], a[0]);
        assertEq(order[1], a[1]);
        assertEq(order[2], b[0], "85 -> 100: x95 stepped over");
        assertEq(order[3], b[1]);
        (uint24 cl, , ) = _cursor();
        assertEq(cl, 105, "waits at the next undrawn level");

        // Nothing owed any more: the leg idles and the router has no work.
        vm.prank(keeper);
        vm.expectRevert();
        game.mineFlip();
    }

    // ---------------------------------------------------------------------
    //                               3. CHUNKS
    // ---------------------------------------------------------------------

    /// @notice A backlog larger than one call's budget, settled across several full mineFlip calls,
    ///         ends in the same state, in the same order, as the same backlog walked one entry per
    ///         call through a minimal budget.
    function test_ChunkSizeDoesNotChangeTheOutcome() public {
        uint256 rngWord = uint256(keccak256("chunks"));
        uint8[] memory ds = _denoms(5, 7, 11);
        // ~25 ETH per winner, so every settle also defers whole half-passes.
        address[] memory winners = _installWinners(5, ds, 40, rngWord, 3_000 ether);

        uint256 snap = vm.snapshotState();
        // Path A: one settle per call.
        bytes memory original = address(game).code;
        vm.etch(address(game), type(DecimatorListWalkHarness).runtimeCode);
        vm.recordLogs();
        uint256 steps;
        // 13 units always reach one settle (a round probe and up to 11 length reads leave at least
        // one unit to start it), and every settle's own charge exhausts the rest, so never two.
        while (true) {
            (uint256 settled, , bool moved) = DecimatorListWalkHarness(payable(address(game))).settleDec(13);
            assertLe(settled, 1, "a minimal budget settles at most one entry");
            if (settled == 0 && !moved) break;
            ++steps;
        }
        (address[] memory orderA, uint256 nA) = _claimedOrder(vm.getRecordedLogs());
        vm.etch(address(game), original);
        uint256[] memory claimA = new uint256[](winners.length);
        uint256[] memory passesA = new uint256[](winners.length);
        for (uint256 i; i < winners.length; ++i) {
            claimA[i] = game.claimableWinningsOf(winners[i]);
            passesA[i] = game.whalePassClaimAmount(winners[i]);
        }
        uint256 futureA = game.futurePrizePoolView();
        uint256 claimablePoolA = game.claimablePoolView();
        assertEq(nA, winners.length, "the minimal walk settles every winner");
        vm.revertToState(snap);

        // Path B: full mineFlip calls until the leg runs dry.
        uint256 calls;
        address[] memory orderB = new address[](winners.length);
        uint256 nB;
        while (true) {
            vm.recordLogs();
            vm.prank(keeper);
            try game.mineFlip() {} catch { break; }
            (address[] memory order, uint256 n) = _claimedOrder(vm.getRecordedLogs());
            if (n == 0) break;
            for (uint256 k; k < n; ++k) orderB[nB++] = order[k];
            ++calls;
        }
        assertGt(calls, 1, "the backlog needed more than one full call");
        assertEq(nB, nA, "same number settled");
        for (uint256 k; k < nA; ++k) assertEq(orderB[k], orderA[k], "same settlement order");
        for (uint256 i; i < winners.length; ++i) {
            assertEq(game.claimableWinningsOf(winners[i]), claimA[i], "same credit per winner");
            assertEq(game.whalePassClaimAmount(winners[i]), passesA[i], "same deferred passes per winner");
        }
        assertEq(game.futurePrizePoolView(), futureA, "same lootbox backing");
        assertEq(game.claimablePoolView(), claimablePoolA, "same reserve left");
    }

    // ---------------------------------------------------------------------
    //                               4. GATES
    // ---------------------------------------------------------------------

    function test_LegIdlesUnderRngLock() public {
        address[] memory winners = _installWinners(5, _denoms(6), 2, uint256(keccak256("lock")), 1 ether);
        _setHeaderByte(19, 1); // rngLockedFlag

        vm.recordLogs();
        vm.prank(keeper);
        try game.mineFlip() {} catch {}
        (, uint256 n) = _claimedOrder(vm.getRecordedLogs());
        assertEq(n, 0, "nothing settles under the lock");
        (, uint64 w, ) = _entry(5, 6, _winningSub(uint256(keccak256("lock")), 6), 0);
        assertGt(w, 0, "entry untouched");

        _setHeaderByte(19, 0);
        _mine();
        assertGt(game.claimableWinningsOf(winners[0]), 0, "settles once the lock lifts");
    }

    function test_LegIdlesAfterGameOver() public {
        uint256 rngWord = uint256(keccak256("over"));
        address[] memory winners = _installWinners(5, _denoms(6), 1, rngWord, 1 ether);
        _setHeaderByte(21, 1); // gameOver

        uint256 before = game.claimableWinningsOf(winners[0]);
        vm.recordLogs();
        vm.prank(keeper);
        try game.mineFlip() {} catch {}
        (, uint256 n) = _claimedOrder(vm.getRecordedLogs());
        assertEq(n, 0, "the walk does not run after game over");
        (, uint64 w, ) = _entry(5, 6, _winningSub(rngWord, 6), 0);
        assertGt(w, 0, "entry untouched");
        assertEq(game.claimableWinningsOf(winners[0]), before, "nothing credited");
    }

    // ---------------------------------------------------------------------
    //                               5. ONCE
    // ---------------------------------------------------------------------

    /// @notice The walk settles each winning entry once and steps over a position a migration
    ///         emptied; a second pass finds nothing left to do.
    function test_EachEntrySettlesOnceAndEmptiedPositionsAreSkipped() public {
        uint24 lvl = 5;
        uint256 rngWord = uint256(keccak256("once"));
        uint8 wsub6 = _winningSub(rngWord, 6);
        uint8 wsub5 = _winningSub(rngWord, 5);
        address a = _playerIn("once-a", 0, lvl, 6, wsub6, true);
        _burn(a, lvl, 6, 1_000 ether);
        // Position 1: a burner that then moves to a losing denom-5 subbucket, emptying it.
        address mover;
        for (uint256 k; ; ++k) {
            mover = makeAddr(string(abi.encodePacked("once-mover-", vm.toString(k))));
            if (_subOf(mover, lvl, 6) == wsub6 && _subOf(mover, lvl, 5) != wsub5) break;
        }
        _burn(mover, lvl, 6, 1_000 ether);
        _burn(mover, lvl, 5, 1_000 ether);
        address c = _playerIn("once-c", 0, lvl, 6, wsub6, true);
        _burn(c, lvl, 6, 2_000 ether);
        _draw(lvl, 3 ether, rngWord);
        (address emptied, uint64 ew, ) = _entry(lvl, 6, wsub6, 1);
        assertEq(emptied, address(0), "position 1 emptied by the migration");
        assertEq(ew, 0);

        vm.recordLogs();
        _mine();
        (address[] memory order, uint256 n) = _claimedOrder(vm.getRecordedLogs());
        assertEq(n, 2, "two winners settle; the emptied position is stepped over");
        assertEq(order[0], a);
        assertEq(order[1], c);
        uint256 creditA = game.claimableWinningsOf(a);
        uint256 creditC = game.claimableWinningsOf(c);
        assertGt(creditA, 0);
        assertGt(creditC, 0);
        assertEq(game.claimableWinningsOf(mover), 0, "the mover's losing entry pays nothing");

        vm.prank(keeper);
        vm.expectRevert();
        game.mineFlip();
        assertEq(game.claimableWinningsOf(a), creditA, "no second credit");
        assertEq(game.claimableWinningsOf(c), creditC, "no second credit");
    }

    /// @notice No Game entry point settles a chosen decimator entry: the walk is the only path.
    function test_NoEntryPointSettlesAChosenEntry() public {
        _installWinners(5, _denoms(6), 1, uint256(keccak256("no-door")), 1 ether);
        bytes[3] memory probes = [
            abi.encodeWithSignature("claimDecimatorJackpot(uint24,uint8,uint32)", uint24(5), uint8(6), uint32(0)),
            abi.encodeWithSignature("claimDecimatorJackpot(address,uint24)", address(this), uint24(5)),
            abi.encodeWithSignature("claimDecimatorJackpotMany(address[],uint24)", new address[](1), uint24(5))
        ];
        for (uint256 i; i < probes.length; ++i) {
            (bool ok, ) = address(game).call(probes[i]);
            assertFalse(ok, "no chosen-entry settlement selector");
        }
        (address owner, uint64 w, ) = _entry(5, 6, _winningSub(uint256(keccak256("no-door")), 6), 0);
        assertTrue(owner != address(0) && w > 0, "the entry is still live");
    }

    // ---------------------------------------------------------------------
    //                               6. BOUNTY
    // ---------------------------------------------------------------------

    /// @dev The walk units the leg spends on the current state, read through the etched harness
    ///      and rolled back, so a bounty assertion can price the knee exactly.
    function _legUnits() internal returns (uint256 units) {
        uint256 snap = vm.snapshotState();
        bytes memory original = address(game).code;
        vm.etch(address(game), type(DecimatorListWalkHarness).runtimeCode);
        (, units, ) = DecimatorListWalkHarness(payable(address(game))).settleDec(OPEN_WEIGHT_BUDGET);
        vm.etch(address(game), original);
        vm.revertToState(snap);
    }

    function _knee(uint256 unit, uint256 units) internal pure returns (uint256) {
        uint256 k = units / 15; // OPEN_HUMAN_ENTRY_WEIGHT
        if (k > 5) k = 5; // OPEN_KNEE
        return (unit * k) / 5;
    }

    function test_SettlingCallPaysOneDecimatorBounty() public {
        _installWinners(5, _denoms(6), 1, uint256(keccak256("bounty-1")), 1 ether);
        uint256 unit0 = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice();
        uint256 units0 = _legUnits();
        vm.recordLogs();
        _mine();
        (uint256 count, uint8 kind, uint256 small) = _bounty(vm.getRecordedLogs());
        assertEq(count, 1, "one bounty");
        assertEq(kind, KIND_DECIMATOR);
        assertEq(small, _knee(unit0, units0), "knee pro-rate on the walk units spent");
        // A settling call always carries the once-per-call first-touch charge, so even one settle
        // reaches the knee: it pays for the ~0.4M of real work such a call does.
        assertGe(units0, 75, "a one-settle call is charged past the knee");
        assertEq(small, unit0, "one settle earns the flat per-call unit");

        _installWinners(15, _denoms(6, 8, 10), 4, uint256(keccak256("bounty-12")), 12 ether);
        _setLevel(15);
        uint256 unit1 = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice();
        vm.recordLogs();
        _mine();
        uint256 full;
        (count, kind, full) = _bounty(vm.getRecordedLogs());
        assertEq(count, 1, "one bounty for a full batch");
        assertEq(kind, KIND_DECIMATOR);
        assertEq(full, unit1, "saturated at the knee: one unit per call");
    }
}
