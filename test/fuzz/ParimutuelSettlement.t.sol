// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {IDegenerusParimutuel} from "../../contracts/interfaces/IDegenerusParimutuel.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

// =====================================================================================
// Mocks etched at ContractAddresses for the market-level suite. Coinflip is the real one.
// =====================================================================================

contract PariSettleMockGame {
    uint24 public round;
    bool public open;
    mapping(address => uint32) public ids;
    mapping(uint32 => address) internal idKey;

    function set(uint24 r, bool o) external {
        round = r;
        open = o;
    }

    function setId(address a, uint32 i) external {
        ids[a] = i;
        idKey[i] = a;
    }

    function growthState(uint24) external view returns (uint256, uint256, uint256, uint24, bool, uint8) {
        return (0, 0, 0, round, open, 0);
    }

    function resolveAccount(uint32 id, address caller) external view returns (address key, address payee, bool authorized) {
        require(id != 0, "E");
        key = idKey[id];
        require(key != address(0), "E");
        payee = key;
        authorized = caller == key;
    }

    function walletIdOf(address a) external view returns (uint32) {
        return ids[a];
    }
}

contract PariSettleMockQuests {
    function marketBetGates(uint32 id, uint24) external view returns (bool, bool, uint32) {
        return (id != 0, false, id);
    }
}

contract PariSettleMockCoin {
    function burnCoin(address, uint256) external {}
}

/// @dev Storage roots of DegenerusParimutuel (scripts/layout/golden/DegenerusParimutuel.json)
///      and Coinflip.coinflipStakePacked (scripts/layout/golden/Coinflip.json). Every reader
///      below is self-checking: a wrong root reads zero where a test expects a written value.
abstract contract PariSettlementSlots {
    uint256 internal constant COUNTS_ROOT = 0;
    uint256 internal constant SIDE_LANES_ROOT = 2;
    uint256 internal constant LAST_BET_ROOT = 3;
    uint256 internal constant SETTLEMENT_SLOT = 4;
    uint256 internal constant STAKE_ROOT = 0;

    uint256 internal constant STAKE = 1_000;
    uint8 internal constant OVER = 1;
    uint8 internal constant UNDER = 2;

    bytes32 internal constant WINNERS_PAID = keccak256("GrowthWinnersPaid(uint24,uint8,uint256,uint256,uint256)");
    bytes32 internal constant BET_PLACED = keccak256("BetPlaced(uint32,uint24,bool,uint256)");
    bytes32 internal constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes4 internal constant CREDIT_BATCH = bytes4(keccak256("creditFlipBatch(uint32[],uint256[])"));

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct PaidRun {
        uint24 round;
        uint8 outcome;
        uint256 firstIndex;
        uint256 count;
        uint256 payout;
    }

    function _sideWord(uint24 round, uint8 side, uint256 wordIndex) internal view returns (uint256) {
        uint256 key = (uint256(round) << 40) | (uint256(side) << 32) | wordIndex;
        return uint256(VM.load(ContractAddresses.PARIMUTUEL, keccak256(abi.encode(key, SIDE_LANES_ROOT))));
    }

    function _sideLane(uint24 round, uint8 side, uint256 index) internal view returns (uint32) {
        return uint32(_sideWord(round, side, index >> 3) >> ((index & 7) << 5));
    }

    function _lastBetWord(uint32 key) internal view returns (uint256) {
        return uint256(VM.load(ContractAddresses.PARIMUTUEL, keccak256(abi.encode(uint256(key), LAST_BET_ROOT))));
    }

    function _countsWord(uint24 round) internal view returns (uint256) {
        return uint256(VM.load(ContractAddresses.PARIMUTUEL, keccak256(abi.encode(uint256(round), COUNTS_ROOT))));
    }

    function _cursor() internal view returns (uint24 round, uint256 paid) {
        uint256 w = uint256(VM.load(ContractAddresses.PARIMUTUEL, bytes32(SETTLEMENT_SLOT)));
        round = uint24(w);
        paid = uint64(w >> 24);
    }

    /// @dev Wallet `id`'s Coinflip stake lane on `day` (8 day lanes per word, keyed day >> 3).
    function _stakeOn(uint24 day, uint32 id) internal view returns (uint256) {
        bytes32 outer = keccak256(abi.encode(uint256(day >> 3), STAKE_ROOT));
        uint256 w = uint256(VM.load(ContractAddresses.COINFLIP, keccak256(abi.encode(uint256(id), outer))));
        return uint32(w >> ((uint256(day) & 7) << 5));
    }

    function _isPaidRun(Vm.Log memory lg) internal pure returns (bool) {
        return lg.emitter == ContractAddresses.PARIMUTUEL && lg.topics.length != 0 && lg.topics[0] == WINNERS_PAID;
    }

    function _decodeRun(Vm.Log memory lg) internal pure returns (PaidRun memory run) {
        run.round = uint24(uint256(lg.topics[1]));
        (run.outcome, run.firstIndex, run.count, run.payout) = abi.decode(lg.data, (uint8, uint256, uint256, uint256));
    }

    function _paidRuns(Vm.Log[] memory logs) internal pure returns (PaidRun[] memory runs) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (_isPaidRun(logs[i])) ++n;
        }
        runs = new PaidRun[](n);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (_isPaidRun(logs[i])) runs[n++] = _decodeRun(logs[i]);
        }
    }
}

// =====================================================================================
// Market level: side arrays, lanes, cursor, settlement chunks (Game, Quests, FLIP mocked;
// Coinflip real, so credits land in the ID-keyed stake ledger).
// =====================================================================================

contract ParimutuelSettlementMarketTest is Test, PariSettlementSlots {
    DegenerusParimutuel private pari;
    PariSettleMockGame private mockGame;
    uint24 private stakeDay;

    function setUp() public {
        vm.warp(86_400 + 40 days);
        vm.etch(ContractAddresses.GAME, address(new PariSettleMockGame()).code);
        vm.etch(ContractAddresses.QUESTS, address(new PariSettleMockQuests()).code);
        vm.etch(ContractAddresses.COIN, address(new PariSettleMockCoin()).code);
        vm.etch(ContractAddresses.COINFLIP, address(new Coinflip()).code);
        DegenerusParimutuel built = new DegenerusParimutuel();
        assertEq(uint256(vm.load(address(built), bytes32(SETTLEMENT_SLOT))), 1, "construction starts the cursor at round 1");
        vm.etch(ContractAddresses.PARIMUTUEL, address(built).code);
        vm.store(ContractAddresses.PARIMUTUEL, bytes32(SETTLEMENT_SLOT), bytes32(uint256(1)));
        pari = DegenerusParimutuel(ContractAddresses.PARIMUTUEL);
        mockGame = PariSettleMockGame(ContractAddresses.GAME);
        stakeDay = GameTimeLib.currentDayIndex() + 1;
    }

    // ---------------------------------------------------------------- helpers

    function _who(uint32 id) private pure returns (address) {
        return address(uint160(0xB0B0_0000 + uint256(id)));
    }

    function _open(uint24 round) private {
        mockGame.set(round, true);
    }

    function _bet(uint32 id, bool over) private {
        address p = _who(id);
        mockGame.setId(p, id);
        vm.prank(p);
        pari.placeBet(0, over);
    }

    function _seal(uint24 round, bool over) private returns (bool) {
        vm.prank(ContractAddresses.GAME);
        return pari.recordGrowth(round, over);
    }

    function _settle(uint256 maxWinners) private returns (bool) {
        vm.prank(ContractAddresses.GAME);
        return pari.settleGrowth(maxWinners);
    }

    function _stake(uint32 id) private view returns (uint256) {
        return _stakeOn(stakeDay, id);
    }

    function _position(uint32 id, uint24 round)
        private
        view
        returns (uint8 side, bool claimed, uint8 outcome, uint256 owed)
    {
        (, , , , side, claimed, outcome, owed) = pari.marketState(_who(id), round);
    }

    /// @dev `nWin` winners (IDs firstId..) and `nLose` losers (IDs after them) on `round`,
    ///      sealed for the winners' side. Returns the round's uniform payout.
    function _round(uint24 round, uint32 firstId, uint256 nWin, uint256 nLose, bool over)
        private
        returns (uint256 payout)
    {
        _open(round);
        for (uint256 i; i < nWin + nLose; ++i) _bet(firstId + uint32(i), i < nWin ? over : !over);
        _seal(round, over);
        payout = nWin == 0 ? 0 : (STAKE * (nWin + nLose)) / nWin;
    }

    function test_GasAwareGrowthMatchesCountedSettlementAtAllMultipliers() public {
        _round(1, 10, 123, 17, true);
        uint256 snap = vm.snapshotState();
        while (!_settle(100)) {}
        bytes32 expected;
        for (uint32 id = 10; id < 150; ++id) expected = keccak256(abi.encode(expected, _stake(id)));
        uint32[4] memory factors = [uint32(10_000), 15_000, 50_000, type(uint32).max];
        for (uint256 f; f < factors.length; ++f) {
            vm.revertToState(snap);
            bool finished;
            for (uint256 calls; calls < 130; ++calls) {
                vm.prank(ContractAddresses.GAME);
                MineFlipGas.Result memory r = pari.runGrowthWork{gas: 9_000_000}(
                    MineFlipGas.budget(8_500_000, factors[f], true));
                assertTrue(r.progressed || r.done);
                if (f == 3) assertLe(r.rewardBasis, 1, "extreme factor still pays a winner");
                if (r.done) { finished = true; break; }
            }
            assertTrue(finished);
            bytes32 actual;
            for (uint32 id = 10; id < 150; ++id) actual = keccak256(abi.encode(actual, _stake(id)));
            assertEq(actual, expected);
        }
    }

    // ---------------------------------------------------------------- bets

    /// One bet per wallet per round, on either side: a repeat and a two-sided entry both revert
    /// AlreadyBet, write nothing, and the next round accepts the wallet again.
    function test_RepeatAndTwoSidedBetsRevertAlreadyBet() public {
        _open(5);
        vm.recordLogs();
        _bet(40, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one BetPlaced");
        assertEq(logs[0].topics[0], BET_PLACED);
        assertEq(uint256(logs[0].topics[1]), 40, "BetPlaced is indexed by the wallet ID");
        assertEq(uint256(logs[0].topics[2]), 5, "and by the round");

        vm.prank(_who(40));
        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        pari.placeBet(0, true);
        vm.prank(_who(40));
        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        pari.placeBet(0, false);

        assertEq(_countsWord(5), 1, "only the first bet is counted");
        assertEq(_sideLane(5, OVER, 1), 0, "a refused repeat appends nothing");
        assertEq(_sideLane(5, UNDER, 0), 0, "a refused two-sided bet appends nothing");

        _open(6);
        _bet(40, false);
        assertEq(_countsWord(6), uint256(1) << 128, "the next round accepts the wallet");
        vm.prank(_who(40));
        vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
        pari.placeBet(0, true);
    }

    /// Eight 32-bit lanes per side-array word: positions 7/8 and 15/16 straddle word boundaries
    /// on both sides, and chunked settlement that stops exactly on those boundaries pays every
    /// position once.
    function test_SideArrayLaneBoundariesBothSides() public {
        _open(1);
        for (uint32 i; i < 17; ++i) {
            _bet(100 + i, true);
            _bet(200 + i, false);
        }
        _checkLaneLayout();
        assertTrue(_seal(1, true));
        _settleOverOnBoundaries();
        _settleUnderOnBoundaries();
    }

    function _checkLaneLayout() private view {
        assertEq(_countsWord(1), 17 | (uint256(17) << 128), "counts are the array lengths");
        for (uint32 i; i < 17; ++i) {
            assertEq(_sideLane(1, OVER, i), 100 + i, "OVER position");
            assertEq(_sideLane(1, UNDER, i), 200 + i, "UNDER position");
        }
        uint256 packed;
        for (uint256 i = 8; i < 16; ++i) packed |= uint256(100 + i) << ((i & 7) << 5);
        assertEq(_sideWord(1, OVER, 1), packed, "positions 8..15 fill word 1 exactly");
        assertEq(_sideWord(1, OVER, 2), 116, "position 16 opens word 2 alone");
        assertEq(_sideWord(1, UNDER, 2), 216, "same on the UNDER side");
        assertEq(_sideWord(1, OVER, 0) >> 224, 107, "position 7 is the top lane of word 0");
    }

    function _settleStopAt(uint256 chunk, uint256 end) private {
        assertFalse(_settle(chunk), "a chunk that spends its budget on winners is not done");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 1);
        assertEq(paid, end, "cursor stops exactly on the boundary");
    }

    function _checkRun(PaidRun memory run, uint8 outcome, uint256 firstIndex, uint256 count) private pure {
        assertEq(run.outcome, outcome);
        assertEq(run.firstIndex, firstIndex);
        assertEq(run.count, count);
        assertEq(run.payout, 2_000);
    }

    /// @dev Round 1, OVER: chunks of 7, 1, 7, 1, 1 end on positions 7, 8, 15, 16, 17.
    function _settleOverOnBoundaries() private {
        vm.recordLogs();
        _settleStopAt(7, 7);
        _settleStopAt(1, 8);
        _settleStopAt(7, 15);
        _settleStopAt(1, 16);
        _settleStopAt(1, 17);
        PaidRun[] memory runs = _paidRuns(vm.getRecordedLogs());
        assertEq(runs.length, 5);
        _checkRun(runs[0], OVER, 0, 7);
        _checkRun(runs[1], OVER, 7, 1);
        _checkRun(runs[2], OVER, 8, 7);
        _checkRun(runs[3], OVER, 15, 1);
        _checkRun(runs[4], OVER, 16, 1);
        assertFalse(_settle(1), "a lone step spends the budget");
        assertTrue(_settle(1), "every sealed round paid");
        for (uint32 i; i < 17; ++i) {
            assertEq(_stake(100 + i), 2_000, "each OVER winner credited once");
            assertEq(_stake(200 + i), 0, "UNDER losers never credited");
        }
    }

    /// @dev Round 2, UNDER: chunks of 8, 7, 4 end on positions 8, 15, then pay 15..16 and finish.
    function _settleUnderOnBoundaries() private {
        _open(2);
        for (uint32 i; i < 17; ++i) {
            _bet(300 + i, false);
            _bet(400 + i, true);
        }
        assertTrue(_seal(2, false));
        vm.recordLogs();
        assertFalse(_settle(8));
        assertFalse(_settle(7));
        assertTrue(_settle(4), "two winners, a step, then the unsealed round");
        PaidRun[] memory runs = _paidRuns(vm.getRecordedLogs());
        assertEq(runs.length, 3);
        _checkRun(runs[0], UNDER, 0, 8);
        _checkRun(runs[1], UNDER, 8, 7);
        _checkRun(runs[2], UNDER, 15, 2);
        for (uint32 i; i < 17; ++i) {
            assertEq(_stake(300 + i), 2_000, "each UNDER winner credited once");
            assertEq(_stake(400 + i), 0, "OVER losers never credited");
        }
    }

    /// lastBetRounds packs eight wallets per word keyed id >> 3: IDs 7 and 8 live in different
    /// words, 8..15 share one, and a write to one lane preserves its neighbours.
    function test_LastBetLanesSplitAtIdEight() public {
        _open(3);
        _bet(7, true);
        _bet(8, false);
        assertEq(_lastBetWord(0), uint256(3) << 224, "ID 7: top lane of word 0");
        assertEq(_lastBetWord(1), 3, "ID 8: bottom lane of word 1");
        _bet(15, true);
        assertEq(_lastBetWord(1), 3 | (uint256(3) << 224), "IDs 8 and 15 share word 1");
        _bet(6, false);
        assertEq(_lastBetWord(0), (uint256(3) << 224) | (uint256(3) << 192), "ID 6 beside ID 7");
        _bet(16, true);
        assertEq(_lastBetWord(2), 3, "ID 16 opens word 2");

        uint32[4] memory taken = [uint32(6), 7, 8, 15];
        for (uint256 i; i < 4; ++i) {
            for (uint256 s; s < 2; ++s) {
                vm.prank(_who(taken[i]));
                vm.expectRevert(DegenerusParimutuel.AlreadyBet.selector);
                pari.placeBet(0, s == 0);
            }
        }

        _open(4);
        _bet(7, false);
        assertEq(_lastBetWord(0), (uint256(4) << 224) | (uint256(3) << 192), "ID 6's lane survives ID 7's write");
        _bet(8, true);
        assertEq(_lastBetWord(1), 4 | (uint256(3) << 224), "ID 15's lane survives ID 8's write");
        _bet(15, false);
        assertEq(_lastBetWord(1), 4 | (uint256(4) << 224));

        (uint8 side, , , ) = _position(7, 3);
        assertEq(side, OVER, "an older round is still found by scanning");
        (side, , , ) = _position(7, 4);
        assertEq(side, UNDER);
        (side, , , ) = _position(16, 4);
        assertEq(side, 0, "a wallet whose last bet is older holds none on the round");
        (side, , , ) = _position(16, 3);
        assertEq(side, OVER);
    }

    // ---------------------------------------------------------------- settlement chunks

    /// The Game's fixed chunk is GROWTH_SETTLE_WINNERS (100). 99 winners settle and report done
    /// in one call; exactly 100 fill the budget, so the next call only steps and reports done;
    /// 101 leave one winner for the second call. Every winner is credited once at
    /// STAKE * total / winCount, losers never, and the burned dust is below winCount.
    function test_ChunkBoundaries99_100_101() public {
        assertEq(MineFlipGasBounds.GROWTH_SETTLE_WINNERS, 100);
        _checkChunkBoundary(1, 1_000, 98);
        _checkChunkBoundary(2, 2_000, 99);
        _checkChunkBoundary(3, 3_000, 100);
        _checkChunkBoundary(4, 4_000, 101);
    }

    /// @dev A round's winners and its step share the chunk budget, and `done` needs one unit
    ///      left to read the unsealed next round: n <= 98 settles and reports done in one call;
    ///      99 pays everyone and steps, 100 pays everyone and stops on the boundary, 101 leaves
    ///      one winner; each of those reports done on its second call.
    function _checkChunkBoundary(uint24 round, uint32 firstId, uint256 n) private {
        uint256 chunk = MineFlipGasBounds.GROWTH_SETTLE_WINNERS;
        uint256 payout = _round(round, firstId, n, 3, true);
        assertEq(payout, (STAKE * (n + 3)) / n);

        vm.recordLogs();
        bool doneFirst = n + 1 < chunk;
        assertEq(_settle(chunk), doneFirst, "one call finishes only with a unit to spare");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, n >= chunk ? round : round + 1);
        assertEq(paid, n >= chunk ? chunk : 0, "a full chunk stops on the 100th winner");
        if (!doneFirst) {
            assertTrue(_settle(chunk), "the next call reports done");
            (r, paid) = _cursor();
        }
        assertEq(r, round + 1);
        assertEq(paid, 0);
        _checkRunsCover(vm.getRecordedLogs(), n, payout, n > chunk ? 2 : 1);
        _checkCredits(firstId, n, 3, payout);
    }

    function _checkRunsCover(Vm.Log[] memory logs, uint256 n, uint256 payout, uint256 expectRuns) private pure {
        PaidRun[] memory runs = _paidRuns(logs);
        uint256 total;
        for (uint256 i; i < runs.length; ++i) {
            assertEq(runs[i].payout, payout);
            total += runs[i].count;
        }
        assertEq(total, n, "every position paid once");
        assertEq(runs.length, expectRuns, "a 100-winner round's second call pays nobody");
    }

    function _checkCredits(uint32 firstId, uint256 nWin, uint256 nLose, uint256 payout) private view {
        uint256 credited;
        for (uint256 i; i < nWin; ++i) {
            uint256 got = _stake(firstId + uint32(i));
            assertEq(got, payout, "winner credited once");
            credited += got;
        }
        for (uint256 i; i < nLose; ++i) assertEq(_stake(firstId + uint32(nWin + i)), 0, "loser never credited");
        assertEq(credited, nWin * payout);
        assertLt(STAKE * (nWin + nLose) - credited, nWin, "dust below one unit per winner");
    }

    /// An empty winning side settles nothing: recordGrowth returns false, the cursor fast-forwards
    /// past the round, and the stage would make no credit call.
    function test_EmptyWinningSideFastForwards() public {
        _open(1);
        _bet(50, false);
        _bet(51, false);
        assertFalse(_seal(1, true), "nobody to pay");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 2, "cursor stepped past the empty round at the seal");
        assertEq(paid, 0);

        vm.expectCall(ContractAddresses.COINFLIP, abi.encodeWithSelector(CREDIT_BATCH), 0);
        assertTrue(_settle(100), "nothing pending");
        assertEq(_stake(50) + _stake(51), 0, "stakes stay burned");
        (uint8 side, bool claimed, uint8 outcome, uint256 owed) = _position(50, 1);
        assertEq(side, UNDER);
        assertFalse(claimed);
        assertEq(outcome, OVER);
        assertEq(owed, 0);
    }

    function _settleExpect(bool done, uint24 round, uint256 paid) private {
        assertEq(_settle(2), done, "done only after the last sealed round");
        (uint24 r, uint256 p) = _cursor();
        assertEq(r, round);
        assertEq(p, paid);
    }

    function _checkRunsInOrderSkipping(Vm.Log[] memory logs, uint24 emptyRound) private pure {
        PaidRun[] memory runs = _paidRuns(logs);
        uint24 last;
        for (uint256 i; i < runs.length; ++i) {
            assertGe(runs[i].round, last, "rounds pay in order");
            assertTrue(runs[i].round != emptyRound, "the empty round pays nobody");
            last = runs[i].round;
        }
    }

    /// Rounds sealed while settlement lags queue behind the cursor: an empty sealed round is
    /// stepped (not fast-forwarded at its seal), rounds pay in order, and `done` arrives only
    /// once every sealed round is paid.
    function test_LaggingRoundsSettleInOrder() public {
        _open(1);
        for (uint32 i; i < 10; ++i) _bet(60 + i, i % 2 == 0);
        assertTrue(_seal(1, true));
        assertFalse(_settle(2));

        _open(2);
        _bet(80, false);
        assertTrue(_seal(2, true), "lagging: round 1 still owes winners");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 1, "no fast-forward while lagging");
        assertEq(paid, 2);

        _open(3);
        _bet(90, true);
        _bet(91, true);
        _bet(92, false);
        assertTrue(_seal(3, true));

        vm.recordLogs();
        _settleExpect(false, 1, 4);
        _settleExpect(false, 2, 0);
        _settleExpect(false, 3, 1);
        _settleExpect(false, 4, 0);
        _settleExpect(true, 4, 0);
        _checkRunsInOrderSkipping(vm.getRecordedLogs(), 2);
        for (uint32 i; i < 10; ++i) assertEq(_stake(60 + i), i % 2 == 0 ? 2_000 : 0);
        assertEq(_stake(80), 0);
        assertEq(_stake(90), 1_500);
        assertEq(_stake(91), 1_500);
        assertEq(_stake(92), 0);
    }

    /// recordGrowth's return: caught up with winners -> true; caught up and empty -> false with
    /// the cursor fast-forwarded; lagging -> true whether the new round is empty or not. A
    /// re-seal keeps the stored side.
    function test_RecordGrowthReturnTruthTable() public {
        _open(1);
        _bet(10, true);
        assertTrue(_seal(1, true), "caught up, winners");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 1);
        assertEq(paid, 0);
        assertTrue(_settle(100));

        _open(2);
        _bet(11, false);
        assertFalse(_seal(2, true), "caught up, empty");
        (r, ) = _cursor();
        assertEq(r, 3);

        _open(3);
        _bet(12, true);
        _bet(13, true);
        assertTrue(_seal(3, true), "caught up, winners");
        _open(4);
        _bet(14, false);
        assertTrue(_seal(4, true), "lagging, empty");
        (r, paid) = _cursor();
        assertEq(r, 3, "lagging empty round is not skipped at its seal");
        assertEq(paid, 0);
        _open(5);
        _bet(15, true);
        assertTrue(_seal(5, true), "lagging, winners");

        assertTrue(_seal(5, false), "a re-seal reads the stored side");
        (, , uint8 outcome, ) = _position(15, 5);
        assertEq(outcome, OVER, "write-once outcome");

        while (!_settle(1)) {}
        assertEq(_stake(12) + _stake(13) + _stake(15), 1_000 + 1_000 + 1_000);
        assertEq(_stake(14), 0);
        assertFalse(_seal(5, false), "a paid round re-sealed leaves nothing pending");
    }

    /// marketState: side, paid and owed on the open round and older rounds, mid-round included.
    function test_MarketStateSidePaidOwed() public {
        _open(1);
        for (uint32 i; i < 10; ++i) _bet(20 + i, true);
        for (uint32 i; i < 3; ++i) _bet(30 + i, false);

        (uint24 openRound, uint128 o, uint128 u, , uint8 side, bool claimed, uint8 outcome, uint256 owed) =
            pari.marketState(_who(22), 1);
        assertEq(openRound, 1);
        assertEq(o, 10);
        assertEq(u, 3);
        assertEq(side, OVER);
        assertFalse(claimed);
        assertEq(outcome, 0, "unsealed");
        assertEq(owed, 0, "nothing owed before the seal");

        _open(2);
        assertTrue(_seal(1, true));
        uint256 payout = (STAKE * 13) / 10;
        (, , outcome, owed) = _position(25, 1);
        assertEq(outcome, OVER);
        assertEq(owed, payout, "sealed and unpaid");

        assertFalse(_settle(4));
        (side, claimed, , owed) = _position(23, 1);
        assertEq(side, OVER);
        assertTrue(claimed, "position 3 paid by the first chunk");
        assertEq(owed, 0);
        (side, claimed, , owed) = _position(24, 1);
        assertFalse(claimed, "position 4 waits for the next chunk");
        assertEq(owed, payout);
        assertEq(_stake(24), 0);
        (side, claimed, outcome, owed) = _position(31, 1);
        assertEq(side, UNDER);
        assertFalse(claimed);
        assertEq(owed, 0, "a loser is never owed");
        (side, claimed, , owed) = _position(99, 1);
        assertEq(side, 0, "no bet");

        _bet(22, false);
        _bet(40, true);
        (openRound, , , , side, , outcome, ) = pari.marketState(_who(22), 2);
        assertEq(openRound, 2);
        assertEq(side, UNDER, "current round");
        assertEq(outcome, 0);
        (side, claimed, , ) = _position(22, 1);
        assertEq(side, OVER, "older round after a newer bet");
        assertTrue(claimed);
        (side, , , ) = _position(24, 2);
        assertEq(side, 0, "last bet older than the round");

        assertTrue(_settle(100));
        (side, claimed, , owed) = _position(24, 1);
        assertTrue(claimed);
        assertEq(owed, 0);
        assertEq(_stake(24), payout);
    }

    function test_SealAndSettleAreGameOnly() public {
        vm.expectRevert(DegenerusParimutuel.OnlyGame.selector);
        pari.recordGrowth(1, true);
        vm.expectRevert(DegenerusParimutuel.OnlyGame.selector);
        pari.settleGrowth(100);
    }

    /// The Game never passes a zero budget; a zero budget is a no-op that reports not done.
    function test_ZeroBudgetChangesNothing() public {
        _round(1, 10, 3, 1, true);
        assertFalse(_settle(0));
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 1);
        assertEq(paid, 0);
    }

    // ---------------------------------------------------------------- agreement fuzz

    uint256 private constant POOL = 96;

    function _poolId(uint256 j, uint256 rot) private pure returns (uint32) {
        return uint32(10 + ((j + rot) % POOL));
    }

    /// One stage call as the Game makes it, with the Game's pending bit modelled: a call made
    /// with the bit clear must find nothing to pay; a call with it set either reports done (and
    /// the cursor sits on the first unsealed round) or moves the cursor.
    function _stageCall(bool bit, uint256 maxWinners, uint24 lastSealed) private returns (bool) {
        (uint24 br, uint256 bp) = _cursor();
        bool done = _settle(maxWinners);
        (uint24 ar, uint256 ap) = _cursor();
        if (!bit) {
            assertTrue(done, "bit clear: every sealed round is paid");
            assertEq(ar, br);
            assertEq(ap, bp);
            return false;
        }
        assertTrue(done || ar != br || ap != bp, "a stage call moves the cursor or reports done");
        if (done) {
            assertEq(ar, lastSealed + 1, "done: cursor on the first unsealed round");
            assertEq(ap, 0);
            return false;
        }
        return true;
    }

    struct FuzzRound {
        uint256 nOver;
        uint256 nUnder;
        uint256 rot;
        bool overWon;
        uint256 rs;
    }

    function _fuzzRound(uint256 seed, uint24 r) private pure returns (FuzzRound memory fr) {
        fr.rs = uint256(keccak256(abi.encode(seed, r)));
        fr.nOver = fr.rs % 41;
        fr.nUnder = (fr.rs >> 8) % 41;
        fr.rot = (fr.rs >> 16) % POOL;
        fr.overWon = (fr.rs >> 24) & 1 == 1;
    }

    /// @dev Bets and seals round `r`, checks the seal's return against the cursor model, books
    ///      the expected payouts, then makes a few interleaved stage calls. Returns the bit.
    function _playRound(uint24 r, FuzzRound memory fr, uint256[] memory expected, bool bit) private returns (bool) {
        _open(r);
        for (uint256 j; j < fr.nOver + fr.nUnder; ++j) _bet(_poolId(j, fr.rot), j < fr.nOver);
        uint256 win = fr.overWon ? fr.nOver : fr.nUnder;
        (uint24 cr, ) = _cursor();
        bool pending = _seal(r, fr.overWon);
        assertEq(pending, cr < r || win != 0, "recordGrowth return");
        if (cr == r && win == 0) {
            (uint24 nr, uint256 np) = _cursor();
            assertEq(nr, r + 1, "caught-up empty round fast-forwards");
            assertEq(np, 0);
        }
        if (pending) bit = true;
        if (win != 0) {
            uint256 payout = (STAKE * (fr.nOver + fr.nUnder)) / win;
            uint256 first = fr.overWon ? 0 : fr.nOver;
            for (uint256 j = first; j < first + win; ++j) expected[_poolId(j, fr.rot) - 10] += payout;
        }
        uint256 calls = (fr.rs >> 32) % 4;
        for (uint256 c; c < calls; ++c) {
            bit = _stageCall(bit, 1 + (uint256(keccak256(abi.encode(fr.rs, c))) % 64), r);
        }
        return bit;
    }

    function _checkRoundViews(uint24 r, FuzzRound memory fr) private view {
        for (uint256 j; j < fr.nOver + fr.nUnder; ++j) {
            (uint8 side, bool claimed, uint8 outcome, uint256 owed) = _position(_poolId(j, fr.rot), r);
            bool isOver = j < fr.nOver;
            assertEq(side, isOver ? OVER : UNDER, "view finds the bet");
            assertEq(outcome, fr.overWon ? OVER : UNDER);
            assertEq(claimed, isOver == fr.overWon, "every winner paid, no loser");
            assertEq(owed, 0);
        }
    }

    /// Random rounds, side sizes, outcomes and chunk sizes, with seals interleaved between stage
    /// calls (lagging included). settleGrowth never reverts; every call with maxWinners >= 1
    /// moves the cursor or reports done; recordGrowth's return matches the cursor model; the
    /// modelled bit never clears with winners owed; each wallet's stake lane ends at exactly the
    /// sum of its payouts; marketState agrees for every bet.
    /// forge-config: default.fuzz.runs = 160
    function testFuzz_SettlementAgreementAndExactPayouts(uint256 seed) public {
        uint24 rounds = uint24(1 + (seed % 5));
        uint256[] memory expected = new uint256[](POOL);
        bool bit;
        for (uint24 r = 1; r <= rounds; ++r) bit = _playRound(r, _fuzzRound(seed, r), expected, bit);
        for (uint256 k; bit && k < 2_000; ++k) bit = _stageCall(bit, 1 + ((k * 7 + seed) % 64), rounds);
        assertFalse(bit, "settlement drains");
        for (uint256 i; i < POOL; ++i) {
            assertEq(_stake(uint32(10 + i)), expected[i], "credited exactly the sum of its payouts");
        }
        for (uint24 r = 1; r <= rounds; ++r) _checkRoundViews(r, _fuzzRound(seed, r));
    }
}

// =====================================================================================
// Selector: the GrowthSettle slot in the Game's derived action order.
// =====================================================================================

contract GrowthSelectorHarness is DegenerusGameMinerModule {
    function seed(MinerAction action) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = today;
        _afkingResetDay = today;
        purchaseStartDay = today;
        level = 10;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        subsFullyProcessed = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 1234;
        _setRngSessionPublished(true);
        _setRngComplete(true);
        _recordDailyRng(today, 1234);
        if (action >= MinerAction.Publish && action <= MinerAction.CertifyRead) _setRngComplete(false);
        if (action == MinerAction.Terminal) gameOver = true;
        if (action == MinerAction.Wait || action == MinerAction.Publish) {
            _setRngComplete(false);
            _setRngRequestActive(true);
            _setRngSessionPublished(false);
            if (action == MinerAction.Wait) rngWordCurrent = RNG_WORD_WAITING;
        }
        if (action == MinerAction.Tickets) ticketsFullyProcessed = false;
        if (action >= MinerAction.DailyGap && action <= MinerAction.DailyPhase) {
            rngLockedFlag = true;
            rngRequestDay = today + (action == MinerAction.DailyGap ? 2 : 1);
            if (action == MinerAction.DailyPhase) _recordDailyRng(rngRequestDay, 5678);
        }
        if (action == MinerAction.Afking) _pendingBoxCount = 1;
        if (action == MinerAction.HumanBoxes) humanReadComplete = false;
        if (action == MinerAction.Degenerette) degeneretteReadCount = 1;
        if (action == MinerAction.Decimator) decBattleQueue = 1;
        if (action == MinerAction.Craps) lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer());
        if (action == MinerAction.PrepareSubscriptions || action == MinerAction.RequestDaily) {
            dailyIdx = today - 1;
            subsFullyProcessed = action == MinerAction.RequestDaily;
        }
        if (action == MinerAction.RequestMidday) _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
    }

    function wireCoordinator() external {
        vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR);
    }

    function setGrowthPending(bool on) external {
        _setGrowthSettlePending(on);
    }

    function growthPending() external view returns (bool) {
        return _growthSettlePending();
    }

    function select() external view returns (uint8) {
        return uint8(_nextMinerAction(address(0)));
    }

    function advanceDue() external view returns (bool) {
        MinerAction action = _nextMinerAction(address(0));
        return action != MinerAction.Idle && action != MinerAction.Wait;
    }

    function seedDeadman() external {
        dailyIdx = _simulatedDayIndex() - 31;
    }

    function seedGameOverPaid() external {
        gameOver = true;
        _goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);
    }

    /// @dev Arbitrary flag mix for the region fuzz; every field the selector reads before the
    ///      settlement check is drawn from `f`.
    function poke(uint256 f) external {
        uint24 today = _simulatedDayIndex();
        level = 10;
        purchaseStartDay = today;
        rngRequestTime = uint48(block.timestamp);
        _recordDailyRng(today, 1234);
        dailyIdx = f & 1 != 0 ? today - 1 : today;
        if (f & (1 << 1) != 0) dailyIdx = today - 31;
        _afkingResetDay = f & (1 << 2) != 0 ? today + 1 : dailyIdx;
        subsFullyProcessed = f & (1 << 3) != 0;
        _setRngComplete(f & (1 << 4) != 0);
        _setRngSessionPublished(f & (1 << 5) != 0);
        _setRngRequestActive(f & (1 << 6) != 0);
        rngWordCurrent = f & (1 << 7) != 0 ? 0 : 1234;
        ticketsFullyProcessed = f & (1 << 8) != 0;
        rngLockedFlag = f & (1 << 9) != 0;
        rngRequestDay = today + 1;
        gameOver = f & (1 << 10) != 0;
        _pendingBoxCount = uint16((f >> 11) & 1);
        humanReadComplete = f & (1 << 12) == 0;
        if (f & (1 << 13) != 0) _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
        _setGrowthSettlePending(f & (1 << 14) != 0);
    }

    function regionFacts()
        external
        view
        returns (bool over, bool live, bool complete, bool locked, bool requestActive, bool dailyDue)
    {
        over = gameOver;
        live = _livenessTriggered();
        complete = _rngComplete();
        locked = rngLockedFlag;
        requestActive = _rngRequestActive();
        dailyDue = _afkingResetDay > dailyIdx || _simulatedDayIndex() > dailyIdx;
    }
}

contract ParimutuelSettlementSelectorTest is Test {
    GrowthSelectorHarness private game;
    uint8 private constant GROWTH_SETTLE = uint8(DegenerusGameStorage.MinerAction.GrowthSettle);

    function setUp() public {
        uint256 start = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 39) * 1 days + 82_620;
        vm.warp(start + 1 hours);
        vm.fee(1 gwei);
        vm.etch(ContractAddresses.GAME, address(new GrowthSelectorHarness()).code);
        game = GrowthSelectorHarness(ContractAddresses.GAME);
        _mockSdgnrs(false);
        _mockMaintenance(false);
        vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("creditFlip(uint32,uint256)"), bytes(""));
        vm.mockCall(
            ContractAddresses.VRF_COORDINATOR,
            abi.encodeWithSelector(IVRFCoordinator.getSubscription.selector),
            abi.encode(uint96(100 ether), uint96(0), uint64(0), address(0), new address[](0))
        );
        game.wireCoordinator();
    }

    function _mockSdgnrs(bool pending) private {
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(pending));
    }

    function _mockMaintenance(bool pending) private {
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(pending));
    }

    function test_GrowthSettleIsValueNineteen() public pure {
        assertEq(GROWTH_SETTLE, 19);
    }

    /// Every action ahead of GrowthSettle keeps its slot with the pending bit set; only Idle and
    /// an eligible mid-day request are displaced, so settlement never runs during the daily lock,
    /// ahead of RNG consumers or certification, ahead of a due daily request, or on the terminal
    /// path, and always runs ahead of the optional mid-day request.
    function test_SelectorTruthTable() public {
        for (uint8 a; a < GROWTH_SETTLE; ++a) {
            uint256 snap = vm.snapshotState();
            DegenerusGameStorage.MinerAction action = DegenerusGameStorage.MinerAction(a);
            game.seed(action);
            _mockSdgnrs(action == DegenerusGameStorage.MinerAction.Redemption);
            _mockMaintenance(action == DegenerusGameStorage.MinerAction.Maintenance);
            assertEq(game.select(), a, "seeded action without the bit");
            game.setGrowthPending(true);
            bool displaced = action == DegenerusGameStorage.MinerAction.Idle
                || action == DegenerusGameStorage.MinerAction.RequestMidday;
            assertEq(game.select(), displaced ? GROWTH_SETTLE : a, "pending bit only displaces Idle and mid-day");
            assertTrue(game.advanceDue() || action == DegenerusGameStorage.MinerAction.Wait, "advanceDue while pending");
            vm.revertToState(snap);
        }
    }

    function test_TerminalAndGameOverNeverSelectSettlement() public {
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        game.setGrowthPending(true);
        assertEq(game.select(), GROWTH_SETTLE);

        uint256 snap = vm.snapshotState();
        game.seedDeadman();
        assertEq(game.select(), uint8(DegenerusGameStorage.MinerAction.Terminal), "liveness takes the terminal path");
        vm.revertToState(snap);

        game.seedGameOverPaid();
        assertEq(game.select(), uint8(DegenerusGameStorage.MinerAction.Idle), "game over with the jackpot paid idles");
        assertFalse(game.advanceDue());
        assertTrue(game.growthPending(), "the bit is simply never served");
    }

    function _settleCall() private pure returns (bytes memory) {
        return abi.encodeWithSelector(IDegenerusParimutuel.runGrowthWork.selector);
    }

    /// The stage passes the fixed chunk once and clears the bit when settleGrowth reports done.
    function test_StageClearsBitOnDone() public {
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        game.setGrowthPending(true);
        vm.etch(ContractAddresses.PARIMUTUEL, hex"00");
        vm.mockCall(ContractAddresses.PARIMUTUEL, _settleCall(), abi.encode(true, true, uint256(0)));
        vm.expectCall(ContractAddresses.PARIMUTUEL, _settleCall(), 1);
        game.mineFlip{gas: 16_000_000}(0);
        assertFalse(game.growthPending(), "done clears the bit");
        assertEq(game.select(), uint8(DegenerusGameStorage.MinerAction.Idle));
    }

    /// A not-done report leaves the bit set and the stage selected. A worker that reported
    /// not-done without moving would pin the stage ahead of the mid-day request; the real
    /// Parimutuel never does (ParimutuelSettlementMarketTest agreement fuzz, and
    /// ParimutuelSettlementProtocolTest.testFuzz_StageAlwaysProgresses on the real Game).
    function test_StageKeepsBitWhileNotDone() public {
        game.seed(DegenerusGameStorage.MinerAction.RequestMidday);
        game.setGrowthPending(true);
        vm.etch(ContractAddresses.PARIMUTUEL, hex"00");
        vm.mockCall(ContractAddresses.PARIMUTUEL, _settleCall(), abi.encode(true, false, uint256(1)));
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), 0);
        game.mineFlip{gas: 4_400_000}(0);
        assertTrue(game.growthPending(), "not done keeps the bit");
        assertEq(game.select(), GROWTH_SETTLE, "still ahead of the eligible mid-day request");
    }

    /// Over arbitrary flag mixes: GrowthSettle is named only with the bit set, outside game over
    /// and liveness, with the RNG cycle certified, no daily request due and no craps maintenance
    /// pending; and with the bit set in that region (no request in flight) it is always named.
    /// forge-config: default.fuzz.runs = 2048
    function testFuzz_SettlementOnlyInItsRegion(uint256 flags, bool maintenance, bool redemption) public {
        if (flags >> 255 == 1) {
            // Half the runs start inside the region (no day due, no deadman, no request, no game
            // over; certified and pending) so the converse is exercised, not just reached.
            flags &= ~uint256(1 | (1 << 1) | (1 << 2) | (1 << 6) | (1 << 10));
            flags |= (1 << 4) | (1 << 14);
            maintenance = false;
        }
        _mockMaintenance(maintenance);
        _mockSdgnrs(redemption);
        game.poke(flags);
        uint8 action = game.select();
        (bool over, bool live, bool complete, , bool requestActive, bool dailyDue) = game.regionFacts();
        bool region = !over && !live && complete && !dailyDue && !maintenance;
        if (action == GROWTH_SETTLE) {
            assertTrue(game.growthPending(), "selected only while pending");
            assertTrue(region, "selected only in the RNG-complete, non-terminal, post-daily region");
        }
        if (game.growthPending() && region && !requestActive) {
            assertEq(action, GROWTH_SETTLE, "pending settlement in its region is always selected");
        }
    }
}

// =====================================================================================
// Real protocol: seal, stage, keeper reward, region on a live day.
// =====================================================================================

abstract contract PariSettlementProtocolBase is DeployProtocol, PariSettlementSlots {
    bytes4 internal constant GROWTH_STATE = bytes4(keccak256("growthState(uint24)"));
    bytes4 internal constant MARKET_GATES = bytes4(keccak256("marketBetGates(uint32,uint24)"));
    bytes32 internal constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 internal constant MINER_BOUNTY = keccak256("MinerBounty(uint8,address,uint256)");
    uint256 internal constant PENDING_BIT = GameSlots.RNG_FLAGS_AND_NUDGES_OFFSET * 8 + 11;
    uint8 internal constant GROWTH_SETTLE = 19;

    uint256 internal simTime;
    uint256 internal bettorNonce;

    function _pending() internal view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(GameSlots.RNG_FLAGS_AND_NUDGES))) >> PENDING_BIT) & 1 == 1;
    }

    /// @dev The advance's response to a `recordGrowth` that returned true.
    function _setPending() internal {
        bytes32 slot = bytes32(GameSlots.RNG_FLAGS_AND_NUDGES);
        vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) | (uint256(1) << PENDING_BIT)));
    }

    function _outcome(uint24 round) internal view returns (uint8 outcome) {
        (, , , , , , outcome, ) = parimutuel.marketState(address(0), round);
    }

    function _stakeDay() internal view returns (uint24) {
        return GameTimeLib.currentDayIndex() + 1;
    }

    /// @dev Bets `nWin` winners and `nLose` losers on `round` (registered wallets, the market's
    ///      gates and open round answered for them), then seals it as GAME and, on a true return,
    ///      sets the Game's pending bit as the advance does.
    function _armRound(uint24 round, uint256 nWin, uint256 nLose, bool over)
        internal
        returns (uint32[] memory winners, uint32[] memory losers)
    {
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(GROWTH_STATE, uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(0))
        );
        winners = new uint32[](nWin);
        losers = new uint32[](nLose);
        for (uint256 i; i < nWin + nLose; ++i) {
            address who = address(uint160(0xBE70_0000 + ++bettorNonce));
            uint32 id = _giveWalletId(who);
            vm.mockCall(address(quests), abi.encodeWithSelector(MARKET_GATES, id), abi.encode(true, false, id));
            vm.prank(address(game));
            coin.mintForGame(who, STAKE);
            vm.prank(who);
            parimutuel.placeBet(0, i < nWin ? over : !over);
            if (i < nWin) winners[i] = id;
            else losers[i - nWin] = id;
        }
        vm.clearMockedCalls();
        vm.prank(address(game));
        if (parimutuel.recordGrowth(round, over)) _setPending();
    }

    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(keccak256(abi.encode(block.timestamp, game.level(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    function _driveDay() internal {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 j = 0; j < 200; j++) {
            _fulfillVrfIfPending();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (!ok) break;
        }
    }

    /// @dev One engine checkpoint: the smallest allowance (250k steps) that makes progress.
    ///      Needs live gas metering.
    function _mineStep() internal returns (bool ok) {
        for (uint256 g = 1_000_000; g <= 16_750_000; g += 250_000) {
            (ok, ) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (ok) return true;
        }
    }
}

contract ParimutuelSettlementProtocolTest is PariSettlementProtocolBase {
    address private constant KEEPER = address(0xC1A9);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        vm.deal(address(game), 100_000 ether);
        _driveDay();
    }

    function _seedNextPool(uint256 targetNext) private {
        bytes32 slot = bytes32(GameSlots.PRIZE_POOLS_PACKED);
        uint256 packed = uint256(vm.load(address(game), slot));
        if ((packed & ((uint256(1) << 128) - 1)) >= targetNext) return;
        vm.store(address(game), slot, bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext));
    }

    function _driveToLiveJackpotPhase() private returns (uint24 round) {
        for (uint256 i = 0; i < 40 && game.level() < 2; i++) {
            if (!game.jackpotPhase()) _seedNextPool(50 ether);
            _driveDay();
        }
        for (uint256 i = 0; i < 40; i++) {
            if (game.jackpotPhase() && !game.rngLocked() && game.level() >= 2) break;
            if (!game.jackpotPhase()) _seedNextPool(200 ether);
            _driveDay();
        }
        require(game.jackpotPhase() && !game.rngLocked(), "harness: no live jackpot phase");
        round = game.level();
        require(round >= 2 && round % 100 > 1 && round % 100 != 99, "harness: skipped round");
    }

    /// @dev Drives whole days until the one that seals `round`, then replays that day one
    ///      checkpoint at a time and returns right after the sealing checkpoint.
    function _driveUntilSealed(uint24 round) private {
        for (uint256 d; d < 60; ++d) {
            if (!game.jackpotPhase()) _seedNextPool(5_000 ether);
            uint256 snap = vm.snapshotState();
            _driveDay();
            if (_outcome(round) == 0) continue;
            vm.revertToState(snap);
            simTime += 1 days + 1;
            vm.warp(simTime);
            vm.resumeGasMetering();
            for (uint256 j; j < 800; ++j) {
                _fulfillVrfIfPending();
                bool ok = _mineStep();
                if (_outcome(round) != 0) {
                    vm.pauseGasMetering();
                    return;
                }
                require(ok, "harness: the sealing day stalled");
            }
            revert("harness: seal not reproduced");
        }
        revert("harness: round never sealed");
    }

    function _keeperReward(uint256 used) private view returns (uint256 reward) {
        uint256 requestTime =
            uint48(uint256(vm.load(address(game), bytes32(GameSlots.RNG_REQUEST_TIME))) >> (GameSlots.RNG_REQUEST_TIME_OFFSET * 8));
        uint256 due = requestTime;
        uint256 reset = block.timestamp - (block.timestamp - 82_620) % 1 days;
        if (reset > due) due = reset;
        uint256 elapsed = block.timestamp > due ? block.timestamp - due : 0;
        uint256 steps = elapsed / 30 minutes;
        if (steps > 4) steps = 4;
        uint256 cap = uint256(500_000_000) << steps;
        uint256 multiplierBps = 3_000 + 4_500 * steps;
        uint256 rate = block.basefee > cap ? cap : block.basefee;
        uint256 numerator = (used - 1_000_000) * rate * 1_000 * multiplierBps;
        uint256 denominator = game.mintPrice() * 10_000;
        if (numerator < (denominator - 1) / 1e18 + 1) return 0;
        reward = numerator / denominator;
        if (reward == 0) reward = 1;
    }

    /// @dev Fixture of the chunked keeper test.
    uint32 private chunkKeeperId;
    uint24 private chunkDay;
    uint256 private chunkPayout;
    uint8 private chunkIdle;

    /// @dev A GrowthSettle-first MinerWork whose reward is the ordinary measured-gas bounty.
    function _checkWorkEvent(bytes memory data) private view returns (uint256 reward) {
        (uint8 firstAction, uint256 used, uint256 paid) = abi.decode(data, (uint8, uint256, uint256));
        assertEq(firstAction, GROWTH_SETTLE);
        assertGt(used, 1_000_000, "a settlement chunk crosses the unpaid floor");
        assertEq(paid, _keeperReward(used), "settlement gas is paid like other work");
        assertGt(paid, 0);
        reward = paid;
    }

    function _bountyAmount(Vm.Log memory lg) private pure returns (uint256 amount) {
        assertEq(address(uint160(uint256(lg.topics[1]))), address(0xC1A9));
        (, amount) = abi.decode(lg.data, (uint8, uint256));
    }

    /// @dev One work event and a matching keeper bounty event. Returns the bounty.
    function _checkKeeperBounty(Vm.Log[] memory logs) private view returns (uint256 bounty) {
        uint256 workEvents;
        uint256 bountyEvent;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory lg = logs[i];
            if (lg.emitter != address(game)) continue;
            if (lg.topics[0] == MINER_WORK) {
                bounty = _checkWorkEvent(lg.data);
                ++workEvents;
            } else if (lg.topics[0] == MINER_BOUNTY) {
                bountyEvent = _bountyAmount(lg);
            }
        }
        assertEq(workEvents, 1);
        assertEq(bountyEvent, bounty, "MinerBounty reports the credited bounty");
    }

    /// @dev Gas selects batch size; emitted runs must cover one contiguous prefix.
    function _keeperChunkCall(uint256 paidBefore) private returns (uint256 paidThis) {
        uint256 keeperBefore = _stakeOn(chunkDay, chunkKeeperId);
        vm.recordLogs();
        vm.prank(KEEPER);
        game.mineFlip{gas: 4_400_000}(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        PaidRun[] memory runs = _paidRuns(logs);
        for (uint256 i; i < runs.length; ++i) {
            assertEq(runs[i].firstIndex, paidBefore + paidThis);
            assertEq(runs[i].payout, chunkPayout);
            paidThis += runs[i].count;
        }
        (uint24 r, uint256 paid) = _cursor();
        if (_pending()) {
            assertEq(game.nextMinerAction(), GROWTH_SETTLE);
            assertEq(r, 1);
            assertEq(paid, paidBefore + paidThis);
        } else {
            assertEq(r, 2);
            assertEq(paid, 0);
            assertEq(game.nextMinerAction(), chunkIdle);
            assertFalse(game.advanceDue());
        }
        uint256 bounty = _checkKeeperBounty(logs);
        assertEq(_stakeOn(chunkDay, chunkKeeperId) - keeperBefore, bounty);
    }

    /// Gas-aware batches pay the whole round exactly once and clear the pending bit.
    function test_StageSettlesInChunksAndClearsOnDone() public {
        vm.pauseGasMetering();
        chunkIdle = game.nextMinerAction();
        assertTrue(chunkIdle != GROWTH_SETTLE, "fixture: idle game");
        assertFalse(game.advanceDue(), "fixture: nothing due");

        (uint32[] memory winners, uint32[] memory losers) = _armRound(1, 250, 3, true);
        assertTrue(_pending(), "seal with winners arms the bit");
        assertEq(game.nextMinerAction(), GROWTH_SETTLE);
        assertTrue(game.advanceDue(), "pending settlement is work");

        chunkKeeperId = _giveWalletId(KEEPER);
        vm.fee(1 gwei);
        chunkDay = _stakeDay();
        chunkPayout = (STAKE * 253) / 250;
        vm.resumeGasMetering();
        uint256 paid;
        uint256 calls;
        while (_pending() && calls++ < 10) paid += _keeperChunkCall(paid);
        assertEq(paid, 250);
        assertFalse(_pending());
        assertGt(calls, 1, "large round spans transactions");
        vm.pauseGasMetering();
        for (uint256 i; i < winners.length; ++i) assertEq(_stakeOn(chunkDay, winners[i]), chunkPayout, "winner credited once");
        for (uint256 i; i < losers.length; ++i) assertEq(_stakeOn(chunkDay, losers[i]), 0, "loser never credited");
    }

    /// Selector/worker agreement on the real Game: whenever the selector names GrowthSettle, a
    /// mineFlip with the stage's admission gas succeeds and either moves the settlement cursor or
    /// clears the bit, and the bit clears exactly when every winner is paid.
    /// forge-config: default.fuzz.runs = 24
    function testFuzz_StageAlwaysProgresses(uint16 rawWinners, uint32 rawGas) public {
        vm.pauseGasMetering();
        uint256 n = bound(rawWinners, 1, 260);
        uint256 gasPerCall = bound(rawGas, 4_300_000, 16_700_000);
        (uint32[] memory winners, ) = _armRound(1, n, 1, false);
        assertTrue(_pending());
        uint24 day = _stakeDay();
        vm.resumeGasMetering();
        uint256 calls;
        while (game.nextMinerAction() == GROWTH_SETTLE) {
            (uint24 br, uint256 bp) = _cursor();
            game.mineFlip{gas: gasPerCall}(0);
            (uint24 ar, uint256 ap) = _cursor();
            assertTrue(!_pending() || ar != br || ap != bp, "selected stage progresses");
            if (!_pending()) {
                assertEq(ar, 2, "cleared only when every winner is paid");
                assertEq(ap, 0);
            }
            assertLt(++calls, 20, "bounded");
        }
        vm.pauseGasMetering();
        assertFalse(_pending());
        uint256 payout = (STAKE * (n + 1)) / n;
        for (uint256 i; i < n; ++i) assertEq(_stakeOn(day, winners[i]), payout);
    }

    /// @dev One checkpoint of a live day: when the selector names GrowthSettle it must be in its
    ///      region, and a call that pays winners must start after the day's word and lock.
    function _walkStep(uint24 today, bool sawLock) private returns (bool locked, bool chosen, uint256 paidNow) {
        _fulfillVrfIfPending();
        uint8 action = game.nextMinerAction();
        bool wordIn = game.rngWordForDay(today) != 0;
        locked = game.rngLocked();
        if (action == GROWTH_SETTLE) {
            assertTrue(wordIn, "the day's word is in");
            assertTrue(game.rngComplete(), "RNG cycle certified");
            assertFalse(locked, "never during the daily lock");
            chosen = true;
        }
        vm.recordLogs();
        assertTrue(_mineStep(), "pending work progresses");
        PaidRun[] memory runs = _paidRuns(vm.getRecordedLogs());
        if (runs.length != 0) {
            assertTrue(wordIn && (sawLock || locked), "a paying call starts after the day's request and lock");
            for (uint256 k; k < runs.length; ++k) paidNow += runs[k].count;
        }
    }

    /// On a live day the stage waits for the day's request, the daily lock and the read cohort:
    /// with settlement pending at the reset, the selector names the daily preparation first and
    /// GrowthSettle only once the day's word is recorded and the RNG cycle is certified.
    function test_LiveDaySettlesOnlyAfterTheDailyCycle() public {
        vm.pauseGasMetering();
        (uint32[] memory winners, ) = _armRound(1, 120, 2, true);
        assertTrue(_pending());
        simTime += 1 days + 1;
        vm.warp(simTime);
        uint8 first = game.nextMinerAction();
        assertTrue(
            first == uint8(DegenerusGameStorage.MinerAction.PrepareSubscriptions)
                || first == uint8(DegenerusGameStorage.MinerAction.Maintenance)
                || first == uint8(DegenerusGameStorage.MinerAction.RequestDaily),
            "a due day comes first"
        );

        uint24 today = game.currentDayView();
        uint256 selected;
        uint256 paidWinners;
        bool sawLock;
        vm.resumeGasMetering();
        for (uint256 i; i < 600 && _pending(); ++i) {
            (bool locked, bool chosen, uint256 paidNow) = _walkStep(today, sawLock);
            sawLock = sawLock || locked;
            if (chosen) ++selected;
            paidWinners += paidNow;
        }
        vm.pauseGasMetering();
        assertFalse(_pending(), "settled the same day");
        assertGt(selected, 0, "the stage was selected between calls");
        assertEq(paidWinners, 120);
        uint256 payout = (STAKE * 122) / 120;
        uint24 day = _stakeDay();
        for (uint256 i; i < winners.length; ++i) assertEq(_stakeOn(day, winners[i]), payout);
    }

    /// Game over and liveness keep the stage off the terminal path: the bit stays set and is
    /// never served.
    function test_TerminalStatesNeverServeSettlement() public {
        vm.pauseGasMetering();
        _armRound(1, 5, 1, true);
        assertEq(game.nextMinerAction(), GROWTH_SETTLE);

        uint256 snap = vm.snapshotState();
        bytes32 slot0 = bytes32(GameSlots.GAME_OVER);
        vm.store(address(game), slot0, bytes32(uint256(vm.load(address(game), slot0)) | (uint256(1) << (GameSlots.GAME_OVER_OFFSET * 8))));
        assertTrue(game.gameOver());
        uint8 action = game.nextMinerAction();
        assertTrue(action == uint8(DegenerusGameStorage.MinerAction.Terminal) || action == uint8(DegenerusGameStorage.MinerAction.Idle));
        assertTrue(_pending());
        vm.revertToState(snap);

        vm.warp(block.timestamp + 32 days);
        assertTrue(game.livenessTriggered(), "fixture: VRF deadman");
        action = game.nextMinerAction();
        assertTrue(action == uint8(DegenerusGameStorage.MinerAction.Terminal) || action == uint8(DegenerusGameStorage.MinerAction.Wait));
        vm.recordLogs();
        for (uint256 i; i < 8; ++i) {
            _fulfillVrfIfPending();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (!ok) break;
        }
        assertEq(_paidRuns(vm.getRecordedLogs()).length, 0, "no settlement on the terminal path");
        assertTrue(_pending());
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, 1);
        assertEq(paid, 0);
    }

    /// @dev A real ticket buyer funded for one bet; returns its wallet ID from the market gate.
    function _buyer(address who, uint24 round) private returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.deal(who, 10 ether);
        vm.prank(who);
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        bool mayBet;
        (mayBet, , id) = quests.marketBetGates(game.walletIdOf(who), round);
        assertTrue(mayBet, "a buyer may bet");
        assertTrue(id != 0, "mayBet carries the buyer's ID");
        vm.prank(address(game));
        coin.mintForGame(who, STAKE);
    }

    function _betAs(address who, bool over) private {
        vm.prank(who);
        parimutuel.placeBet(0, over);
    }

    /// @dev Steps the engine until the pending bit clears and returns the logs of those steps.
    function _stepUntilClear() private returns (Vm.Log[] memory logs) {
        vm.recordLogs();
        vm.resumeGasMetering();
        for (uint256 i; i < 800 && _pending(); ++i) {
            _fulfillVrfIfPending();
            if (!_mineStep()) {
                simTime += 1 days + 1;
                vm.warp(simTime);
            }
        }
        vm.pauseGasMetering();
        assertFalse(_pending(), "the stage cleared the bit");
        logs = vm.getRecordedLogs();
    }

    function _assertLoneWinnerPaid(Vm.Log[] memory logs, uint24 round, uint8 outcome, uint32 winnerId) private pure {
        PaidRun[] memory runs = _paidRuns(logs);
        assertEq(runs.length, 1);
        assertEq(runs[0].round, round);
        assertEq(runs[0].outcome, outcome);
        assertEq(runs[0].count, 1);
        assertEq(runs[0].payout, 2 * STAKE, "the lone winner takes both stakes");
        bool credited;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != ContractAddresses.COINFLIP || logs[i].topics[0] != STAKE_UPDATED) continue;
            if (uint256(logs[i].topics[1]) != winnerId) continue;
            (uint256 amount, ) = abi.decode(logs[i].data, (uint256, uint256));
            if (amount == 2 * STAKE) credited = true;
        }
        assertTrue(credited, "credited to the winner's ID");
    }

    /// The real advance arms the bit from the seal's return: a round whose winning side holds a
    /// bet sets slot-0 bit 251 at the sealing checkpoint and the stage pays it; the same history
    /// with only the losing side bet leaves the bit clear, fast-forwards the cursor, and never
    /// selects the stage.
    function test_RealSealArmsBitOnlyForANonEmptyWinningSide() public {
        vm.pauseGasMetering();
        uint24 round = _driveToLiveJackpotPhase();
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        uint32 idA = _buyer(alice, round);
        uint32 idB = _buyer(bob, round);
        assertTrue(idA != idB);

        uint256 s0 = vm.snapshotState();
        _betAs(alice, true);
        _betAs(bob, false);
        _driveUntilSealed(round);
        uint8 outcome = _outcome(round);
        assertTrue(outcome == OVER || outcome == UNDER);
        assertTrue(_pending(), "a non-empty winning side sets bit 251 at the seal");
        (uint24 r, uint256 paid) = _cursor();
        assertEq(r, round, "earlier empty rounds were stepped at their seals");
        assertEq(paid, 0);
        _assertLoneWinnerPaid(_stepUntilClear(), round, outcome, outcome == OVER ? idA : idB);
        (r, ) = _cursor();
        assertEq(r, round + 1);

        vm.revertToState(s0);
        _betAs(alice, outcome == UNDER);
        _driveUntilSealed(round);
        assertEq(_outcome(round), outcome, "same history, same outcome");
        assertFalse(_pending(), "an empty winning side leaves bit 251 clear");
        (r, ) = _cursor();
        assertEq(r, round + 1, "the cursor fast-forwards past the empty round");
        vm.recordLogs();
        vm.resumeGasMetering();
        for (uint256 i; i < 400; ++i) {
            assertTrue(game.nextMinerAction() != GROWTH_SETTLE, "the stage is never selected");
            _fulfillVrfIfPending();
            if (!_mineStep()) break;
        }
        vm.pauseGasMetering();
        assertEq(_paidRuns(vm.getRecordedLogs()).length, 0);
    }
}

// =====================================================================================
// mayBet => id != 0 over the Game's doors (real protocol, no mocks).
// =====================================================================================

contract ParimutuelBetGateDoorsTest is DeployProtocol {
    address private constant OPERATOR = address(0x0FE7);
    address private constant DEITY = address(0xDE17);
    address private constant FRESH = address(0xF4E5_0001);
    uint8 private constant DEITY_SYMBOL = 7;
    uint256 private constant ACTORS = 6;
    uint256 private constant KINDS = 15;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 20 days);
        vm.deal(OPERATOR, 10_000 ether);
        vm.deal(DEITY, 10_000 ether);
        vm.prank(DEITY);
        game.purchaseDeityPass{value: 200 ether}(0, DEITY_SYMBOL, 0);
        vm.prank(address(game));
        coin.mintForGame(DEITY, 1_000_000);
        for (uint256 i; i < ACTORS; ++i) {
            address a = _actor(i);
            vm.deal(a, 10_000 ether);
        }
    }

    function _actor(uint256 i) private pure returns (address) {
        return address(uint160(0xD0_0500 + i));
    }

    function _assertGate(address who) private view {
        uint24 lvl = game.level();
        for (uint24 k; k < 2; ++k) {
            (bool mayBet, , uint32 id) = quests.marketBetGates(game.walletIdOf(who), lvl + k);
            assertTrue(!mayBet || id != 0, "mayBet implies a wallet ID");
            assertEq(id, game.walletIdOf(who), "gate ID is the mint-word ID");
        }
    }

    function _assertAll() private view {
        for (uint256 i; i < ACTORS; ++i) _assertGate(_actor(i));
        _assertGate(OPERATOR);
        _assertGate(DEITY);
        _assertGate(FRESH);
        (bool freshMay, bool freshEarns, uint32 freshId) = quests.marketBetGates(game.walletIdOf(FRESH), game.level());
        assertFalse(freshMay || freshEarns, "an untouched wallet may not bet");
        assertEq(freshId, 0);
    }

    function _idOrRegister(address who) private returns (uint32 id) {
        id = game.walletIdOf(who);
        if (id == 0) id = _giveWalletId(who);
    }

    function _call(address from, uint256 value, bytes memory data) private returns (bool ok) {
        vm.prank(from);
        (ok, ) = address(game).call{value: value}(data);
    }

    /// @dev One door, chosen by `kind`, for `who` (with `other` as a gift counterparty).
    function _door(uint256 kind, address who, address other, uint256 r) private returns (bool ok) {
        uint256 price = game.mintPrice();
        if (kind == 0) {
            ok = _call(who, price, abi.encodeCall(DegenerusGame.purchase, (uint32(0), 400, 0, bytes32(0), MintPaymentKind.DirectEth, false)));
        } else if (kind == 1) {
            ok = _call(who, price, abi.encodeCall(DegenerusGame.purchase, (uint32(0), 0, 1, bytes32(0), MintPaymentKind.DirectEth, false)));
        } else if (kind == 2) {
            // An operator acts only for an allocated account; a wallet with no ID is bought for by its own caller.
            uint32 whoId = game.walletIdOf(who);
            if (whoId != 0) {
                vm.prank(who);
                game.setOperatorApproval(0, OPERATOR, true);
            }
            ok = _call(OPERATOR, price, abi.encodeCall(DegenerusGame.purchase, (whoId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false)));
        } else if (kind == 3) {
            ok = _call(who, 4 ether, abi.encodeCall(DegenerusGame.purchaseWhalePass, (uint32(0), 1, bytes32(0))));
        } else if (kind == 4) {
            ok = _call(who, 1 ether, abi.encodeCall(DegenerusGame.purchaseLazyPass, (uint32(0), bytes32(0))));
        } else if (kind == 5) {
            // Symbols 0 and 6 are the protocol's, 7 is DEITY's.
            ok = _call(who, 200 ether, abi.encodeCall(DegenerusGame.purchaseDeityPass, (uint32(0), uint8(8 + (r >> 32) % 24), bytes32(0))));
        } else if (kind == 6) {
            ok = _call(who, 0.01 ether, abi.encodeCall(DegenerusGame.placeDegeneretteBet, (uint32(0), 0, uint128(0.01 ether), 1, 3)));
        } else if (kind == 7) {
            ok = _call(who, 0.01 ether, abi.encodeCall(DegenerusGame.placeDegeneretteBet, (game.walletIdOf(other), 0, uint128(0.01 ether), 1, 3)));
        } else if (kind == 8) {
            ok = _call(DEITY, 0, abi.encodeCall(DegenerusGame.smite, (uint256(DEITY_SYMBOL), _idOrRegister(who))));
        } else if (kind == 9) {
            _giveWalletId(who);
            ok = true;
        } else if (kind == 10) {
            vm.prank(other);
            game.playerActivityScoreCached(who);
            ok = true;
        } else if (kind == 11) {
            vm.prank(address(game));
            coin.mintForGame(who, 1_000);
            vm.prank(who);
            (ok, ) = address(coinflip).call(abi.encodeCall(Coinflip.depositCoinflip, (uint32(0), 1_000)));
        } else if (kind == 12) {
            ok = _call(DEITY, 0, abi.encodeCall(DegenerusGame.decurse, (_idOrRegister(who))));
        } else if (kind == 13) {
            ok = _call(who, 1 ether, abi.encodeCall(DegenerusGame.depositAfkingFunding, (_idOrRegister(who))));
        } else {
            ok = _call(who, 0.05 ether, abi.encodeCall(DegenerusGame.buyPresaleBox, (uint32(0), 0.05 ether)));
        }
    }

    /// Every Game door that writes a mint-word field registers the wallet first, so the market's
    /// gate never answers (true, _, 0). Registration alone and a smite alone never open it.
    /// forge-config: default.fuzz.runs = 96
    function testFuzz_MayBetImpliesWalletId(uint256 seed) public {
        _assertAll();
        for (uint256 i; i < 12; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            _door(r % KINDS, _actor((r >> 8) % ACTORS), _actor((r >> 16) % ACTORS), r);
            _assertAll();
        }
    }

    /// Each door succeeds on its own and leaves the gate consistent.
    function test_EveryDoorKeepsTheGate() public {
        bool[KINDS] memory expectOk = [true, true, true, true, true, true, true, true, true, true, true, true, true, true, true];
        for (uint256 k; k < KINDS; ++k) {
            uint256 snap = vm.snapshotState();
            address who = _actor(k % ACTORS);
            address other = _actor((k + 1) % ACTORS);
            if (k == 12) _door(8, who, other, 0);
            if (k == 13) _giveWalletId(who);
            if (k == 14) _door(3, who, other, 0);
            bool ok = _door(k, who, other, k);
            assertEq(ok, expectOk[k], string.concat("door ", vm.toString(k)));
            _assertAll();
            vm.revertToState(snap);
        }
    }

    function _openRound() private returns (uint24 round) {
        round = 5;
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(bytes4(keccak256("growthState(uint24)")), uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(0))
        );
    }

    /// A smite writes only the curse field of a registered, never-bought word: no bet.
    function test_SmiteOnlyWordCannotBet() public {
        address target = _actor(0);
        uint32 targetId = _giveWalletId(target);
        vm.prank(DEITY);
        game.smite(DEITY_SYMBOL, targetId);
        assertGt(game.curseCountOf(target), 0, "fixture: smitten");
        assertEq(game.walletIdOf(target), targetId, "a smite allocates no new ID");
        (bool mayBet, bool earns, uint32 id) = quests.marketBetGates(game.walletIdOf(target), game.level());
        assertFalse(mayBet || earns);
        assertEq(id, targetId);
        _openRound();
        vm.prank(address(game));
        coin.mintForGame(target, STAKE_UNITS);
        vm.prank(target);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeBet(0, true);
    }

    uint256 private constant STAKE_UNITS = 1_000;

    /// Registration writes only the ID field (by a hook or by a Coinflip deposit): no bet.
    function test_RegistrationOnlyWordCannotBet() public {
        address hooked = _actor(1);
        uint32 id = _giveWalletId(hooked);
        assertGt(id, 0);
        (bool mayBet, , uint32 gateId) = quests.marketBetGates(game.walletIdOf(hooked), game.level());
        assertFalse(mayBet, "an ID alone is not participation");
        assertEq(gateId, id);

        address flipper = _actor(2);
        vm.prank(address(game));
        coin.mintForGame(flipper, STAKE_UNITS * 2);
        vm.prank(flipper);
        coinflip.depositCoinflip(0, STAKE_UNITS);
        assertGt(game.walletIdOf(flipper), 0, "a deposit registers");
        (mayBet, , ) = quests.marketBetGates(game.walletIdOf(flipper), game.level());
        assertFalse(mayBet, "a Coinflip registration is not participation");

        _openRound();
        vm.prank(hooked);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeBet(0, true);
        vm.prank(flipper);
        vm.expectRevert(DegenerusParimutuel.NotEligible.selector);
        parimutuel.placeBet(0, true);
    }

    /// A real buyer's bet is booked under its wallet ID.
    function test_BuyerBetBooksItsWalletId() public {
        address buyer = _actor(3);
        uint256 price = game.mintPrice();
        vm.prank(buyer);
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        uint32 id = game.walletIdOf(buyer);
        assertGt(id, 0);
        uint24 round = _openRound();
        vm.prank(address(game));
        coin.mintForGame(buyer, STAKE_UNITS);
        vm.recordLogs();
        vm.prank(buyer);
        parimutuel.placeBet(0, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(parimutuel) || logs[i].topics[0] != keccak256("BetPlaced(uint32,uint24,bool,uint256)")) continue;
            assertEq(uint256(logs[i].topics[1]), id);
            assertEq(uint256(logs[i].topics[2]), round);
            seen = true;
        }
        assertTrue(seen);
        (, , , , uint8 side, , , ) = parimutuel.marketState(buyer, round);
        assertEq(side, 1);
    }
}
