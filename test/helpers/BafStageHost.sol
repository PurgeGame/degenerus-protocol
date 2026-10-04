// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {BucketSeed} from "./BucketSeed.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";

/// @dev Production facade plus seeding and native worker seams for the BAF award stage.
///      The seams delegatecall the production modules exactly as the engine does; nothing
///      here replaces production work inside a measured or asserted call.
contract BafStageHost is DegenerusGame, BucketSeed {
    struct WorkView {
        uint128 budget;
        uint128 paid;
        uint32 traits;
        uint24 lvl;
        uint16 winner;
        uint8 kind;
        uint8 quadrant;
        bool finalDay;
        uint32 directTicketRound;
        bool directTickets;
    }

    struct PoolView {
        uint128 next;
        uint128 future;
        uint128 pendingNext;
        uint128 pendingFuture;
        bool frozen;
        uint256 claimable;
        uint256 current;
    }

    /// @dev A delivered, published daily session on today's word with every queue read
    ///      certified: the state `runDailyPhase` requires. `jackpot` selects the jackpot phase
    ///      (BAF stage) or the locked last-purchase day (consolidation).
    function seedSession(uint24 lvl, uint256 word, bool jackpot) external {
        uint24 day = _simulatedDayIndex();
        level = lvl;
        jackpotPhaseFlag = jackpot;
        lastPurchaseDay = !jackpot;
        phaseTransitionActive = false;
        jackpotCounter = 0;
        rngLockedFlag = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        dailyIdx = day - 1;
        purchaseStartDay = day - 3;
        rngRequestDay = day;
        _recordDailyRng(day, word);
        rngRequestTime = uint48(block.timestamp) & ~uint48(1);
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        dailyTicketBudgetsPacked = 0;
        dailyJackpotCoinTicketsPending = false;
        delete jackpotWork;
    }

    function seedPools(uint128 nextPool, uint128 futurePool, uint128 current, uint24 prevLvl, uint256 prevPool) external {
        _setPrizePools(nextPool, futurePool);
        currentPrizePool = current;
        levelPrizePool[prevLvl] = prevPool;
    }

    /// @dev The daily commitment freeze the request opens: fresh contributions route to the
    ///      pending pools until the unlock.
    function seedFrozen(bool frozen, uint128 pendingNext, uint128 pendingFuture) external {
        prizePoolFrozen = frozen;
        _setPendingPools(pendingNext, pendingFuture);
    }

    /// @dev The BAF candidate population of bracket `lvl`: every trait bucket of `lvl` and
    ///      `lvl + 1` holds four distinct holders drawn cyclically from `traitHolders` wallets
    ///      at `traitBase + 1..`, and every far-future level `lvl + 2..lvl + 99` queues
    ///      `farPerLevel` wallets of its own at `farBase + target * 16 + 1..`. Far-future
    ///      headers in that range start empty.
    function seedBracketHolders(uint24 lvl, uint160 traitBase, uint256 traitHolders, uint160 farBase, uint256 farPerLevel)
        external
    {
        for (uint256 t; t < 256; ++t) {
            for (uint256 k; k < 4; ++k) {
                _seedBucket(lvl, uint8(t), traitHolder(traitBase, traitHolders, t * 4 + k), 1);
                _seedBucket(lvl + 1, uint8(t), traitHolder(traitBase, traitHolders, t * 4 + k + 2), 1);
            }
        }
        for (uint24 target = lvl + 2; target <= lvl + 99; ++target) {
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(target))];
            assembly ("memory-safe") { sstore(q.slot, 0) }
            for (uint256 k; k < farPerLevel; ++k) {
                _seedQueued(_tqFarFutureKey(target), target, farHolder(farBase, target, k), uint80(4 << 8));
            }
        }
    }

    function traitHolder(uint160 base, uint256 holders, uint256 index) public pure returns (address) {
        return address(base + uint160(index % holders) + 1);
    }

    function farHolder(uint160 base, uint24 target, uint256 k) public pure returns (address) {
        return address(base + uint160(uint256(target) * 16 + k) + 1);
    }

    /// @dev Arms the award stage as consolidation leaves it: kind 7, pool `budget`, `positions`
    ///      (2R + 3) awards, cursor 0 and `reserve` uncredited ETH already counted in claimablePool.
    function armBaf(uint24 lvl, uint128 budget, uint128 reserve, uint8 quadrant, uint32 positions) external {
        jackpotWork = JackpotWork({
            budget: budget,
            paid: reserve,
            traits: positions,
            lvl: lvl,
            winner: 0,
            kind: 7,
            quadrant: quadrant,
            finalDay: false,
            directTicketRound: 0,
            directTickets: false
        });
        claimablePool += reserve;
    }

    function seedWork(uint8 kind, uint24 lvl, uint128 budget, uint128 paid, uint32 traits, uint16 winner) external {
        jackpotWork.kind = kind;
        jackpotWork.lvl = lvl;
        jackpotWork.budget = budget;
        jackpotWork.paid = paid;
        jackpotWork.traits = traits;
        jackpotWork.winner = winner;
    }

    /// @dev The production queue sink with the arguments one logged `EntriesQueued` reports.
    function replayQueued(address buyer, uint24 targetLevel, uint32 entries) external {
        _queueEntries(buyer, targetLevel, entries, true);
    }

    function daily(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return abi.decode(
            _native(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runDailyPhase(uint256)", allowance)),
            (MineFlipGas.Result)
        );
    }

    function terminal(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return abi.decode(
            _native(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runTerminalPhase(uint256)", allowance)),
            (MineFlipGas.Result)
        );
    }

    /// @dev The facade route of the award stage: GAME delegatecalls the jackpot module, which
    ///      forwards to the draw module.
    function bafAwardsVia(uint256 word, uint256 allowance) external returns (MineFlipGas.Result memory) {
        return abi.decode(
            _native(
                ContractAddresses.GAME_JACKPOT_MODULE,
                abi.encodeWithSignature("runBafAwards(uint256,uint256)", word, allowance)
            ),
            (MineFlipGas.Result)
        );
    }

    function workView() external view returns (WorkView memory w) {
        JackpotWork memory j = jackpotWork;
        w = WorkView(j.budget, j.paid, j.traits, j.lvl, j.winner, j.kind, j.quadrant, j.finalDay,
            j.directTicketRound, j.directTickets);
    }

    function poolView() external view returns (PoolView memory p) {
        (p.next, p.future) = _getPrizePools();
        (p.pendingNext, p.pendingFuture) = _getPendingPools();
        p.frozen = prizePoolFrozen;
        p.claimable = claimablePool;
        p.current = currentPrizePool;
    }

    function dailyWord() external view returns (uint256) {
        return _recordedDailyWord(rngRequestDay);
    }

    function farQueueLength(uint24 lvl) external view returns (uint256) {
        return _ticketQueueLength(_tqFarFutureKey(lvl));
    }

    function nearQueueLength(uint24 lvl) external view returns (uint256) {
        return _ticketQueueLength(lvl) + _ticketQueueLength(lvl | TICKET_SLOT_BIT);
    }

    function whalePassesOf(address player) external view returns (uint256) {
        return whalePassClaims[player];
    }

    function claimableOf(address player) external view returns (uint256) {
        return _claimableOf(player);
    }

    function liabilities() external view returns (uint256) {
        return claimablePool;
    }

    function livenessView() external view returns (bool) {
        return _livenessTriggered();
    }

    function _native(address target, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory reason) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        return reason;
    }
}

/// @dev A real pre-stage BAF bracket on the production facade: scored candidates in every trait
///      bucket of the bracket level and the next, scored far-future queues over lvl + 2..lvl + 99,
///      a full top-four board and an armed final-day depositor draw. Helpers derive the award
///      schedule (round count, amounts, legs), its reserved ETH term and each award's expected
///      events from the pool alone, and read the drawn winners from `DegenerusJackpots`
///      (`bafPairWinners`, `bafHeadWinner`).
abstract contract BafBracketFixture is DeployProtocol {
    uint256 internal constant BAF_GROUP = 8;
    uint256 internal constant BAF_BASE_ROUNDS = 48;
    uint256 internal constant BAF_ROUNDS_ANCHOR = 125 ether;
    uint256 internal constant BAF_MAX_ROUNDS = 48 * 32;
    uint8 internal constant STAGE_BAF = 19;
    uint256 internal constant BAF_TRAIT_SENTINEL = 420;
    uint8 internal constant WHALE_SRC_BAF_DIRECT = 2;
    uint8 internal constant WHALE_SRC_AWARD_TICKETS = 3;

    uint160 internal constant TRAIT_BASE = 0xBA10000000;
    uint256 internal constant TRAIT_HOLDERS = 61;
    uint160 internal constant FAR_BASE = 0xBA20000000;
    uint256 internal constant FAR_PER_LEVEL = 4;
    uint160 internal constant TOP_BASE = 0xBA30000000;
    uint160 internal constant DEPOSITOR_BASE = 0xBA40000000;
    uint256 internal constant DEPOSITORS = 3;
    uint24 internal constant DRAW_DAY = 41;

    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    bytes32 internal constant ETH_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant WHALE_SIG = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
    bytes32 internal constant CREDIT_SIG = keccak256("PlayerCredited(address,uint256)");
    bytes32 internal constant QUEUED_SIG = keccak256("EntriesQueued(address,uint24,uint32)");

    /// @dev One award event: ETH legs carry the amount, ticket rolls the source floor, whale
    ///      legs `halves << 8 | source`.
    struct Mark {
        bytes32 sig;
        address who;
        uint256 value;
    }

    BafStageHost internal host;

    /// @dev Production bytecode replaced by the host at a raw jump to `lvl`; earlier levels'
    ///      queues count as drained.
    function _hostAt(uint24 lvl, uint256 word, bool jackpot) internal {
        TQ.retireCompleted(address(game), lvl + 1);
        vm.etch(address(game), type(BafStageHost).runtimeCode);
        host = BafStageHost(payable(address(game)));
        host.seedSession(lvl, word, jackpot);
    }

    /// @dev Candidates and scores for bracket `lvl` (the game level of the stage).
    function _seedBracket(uint24 lvl) internal {
        host.seedBracketHolders(lvl, TRAIT_BASE, TRAIT_HOLDERS, FAR_BASE, FAR_PER_LEVEL);
        vm.startPrank(ContractAddresses.COINFLIP);
        for (uint256 i; i < TRAIT_HOLDERS; ++i) {
            jackpots.recordBafFlip(_traitHolder(i), lvl, (i + 1) * 10 ether);
        }
        for (uint24 target = lvl + 2; target <= lvl + 99; ++target) {
            for (uint256 k; k < FAR_PER_LEVEL; ++k) {
                jackpots.recordBafFlip(_farHolder(target, k), lvl, (uint256(target) * 16 + k + 1) * 1 ether);
            }
        }
        for (uint256 i; i < 4; ++i) {
            jackpots.recordBafFlip(_topBettor(i), lvl, (i + 1) * 1_000_000 ether);
        }
        vm.stopPrank();
    }

    /// @dev The armed final purchase day's direct-deposit book (head slot 1's draw).
    function _armDepositDraw() internal {
        for (uint256 i; i < DEPOSITORS; ++i) {
            vm.store(address(coinflip), keccak256(abi.encode((uint256(DRAW_DAY) << 32) | i, uint256(8))),
                bytes32((uint256(uint160(_depositor(i))) << 96) | ((i + 1) * 100)));
        }
        vm.store(address(coinflip), keccak256(abi.encode(uint256(DRAW_DAY), uint256(5))),
            bytes32((DEPOSITORS << 96) | (DEPOSITORS * 100)));
        vm.prank(address(game));
        coinflip.armBafDraw(DRAW_DAY);
        (, uint96 weight, uint32 drawn) = coinflip.bafDrawInfo();
        assertEq(drawn, DEPOSITORS, "draw layout");
        assertEq(weight, DEPOSITORS * 100, "draw weight");
    }

    function _traitHolder(uint256 i) internal pure returns (address) {
        return address(TRAIT_BASE + uint160(i) + 1);
    }

    function _farHolder(uint24 target, uint256 k) internal pure returns (address) {
        return address(FAR_BASE + uint160(uint256(target) * 16 + k) + 1);
    }

    function _topBettor(uint256 i) internal pure returns (address) {
        return address(TOP_BASE + uint160(i) + 1);
    }

    function _depositor(uint256 i) internal pure returns (address) {
        return address(DEPOSITOR_BASE + uint160(i) + 1);
    }

    /// @dev Every wallet that can hold a BAF award in this fixture.
    function _candidates(uint24 lvl) internal pure returns (address[] memory all) {
        all = new address[](TRAIT_HOLDERS + 98 * FAR_PER_LEVEL + 4 + DEPOSITORS);
        uint256 n;
        for (uint256 i; i < TRAIT_HOLDERS; ++i) all[n++] = _traitHolder(i);
        for (uint24 target = lvl + 2; target <= lvl + 99; ++target) {
            for (uint256 k; k < FAR_PER_LEVEL; ++k) all[n++] = _farHolder(target, k);
        }
        for (uint256 i; i < 4; ++i) all[n++] = _topBettor(i);
        for (uint256 i; i < DEPOSITORS; ++i) all[n++] = _depositor(i);
    }

    // ---------------------------------------------------------------------
    // Award schedule (pure in the pool)
    // ---------------------------------------------------------------------

    /// @dev Scatter rounds the pool selects: 48 below 500 ETH, doubled at each fourfold step from
    ///      500 ETH up to 1,536.
    function _bafRounds(uint256 pool) internal pure returns (uint256 rounds) {
        rounds = BAF_BASE_ROUNDS;
        for (uint256 step = 4 * BAF_ROUNDS_ANCHOR; rounds < BAF_MAX_ROUNDS && pool >= step; step *= 4) {
            rounds *= 2;
        }
    }

    /// @dev 2R scatter positions plus the three head awards.
    function _bafPositions(uint256 pool) internal pure returns (uint256) {
        return 2 * _bafRounds(pool) + 3;
    }

    function _bafGroups(uint256 pool) internal pure returns (uint256) {
        return (_bafPositions(pool) + BAF_GROUP - 1) / BAF_GROUP;
    }

    function _bafAmount(uint256 pool, uint256 i) internal pure returns (uint256) {
        uint256 rounds = _bafRounds(pool);
        if (i < 2 * rounds) return i & 1 == 0 ? (pool / 2) / rounds : ((pool * 30) / 100) / rounds;
        return i == 2 * rounds ? pool / 10 : pool / 20;
    }

    /// @dev Small awards pay ETH for the best of an even round and the second of an odd round.
    function _bafEthLeg(uint256 i) internal pure returns (bool) {
        return ((i >> 1) ^ i) & 1 == 0;
    }

    /// @dev The claimable ETH award i credits when filled.
    function _bafEthTerm(uint256 pool, uint256 i) internal pure returns (uint256) {
        uint256 amount = _bafAmount(pool, i);
        if (amount >= pool / 20) {
            uint256 lootbox = amount - amount / 2;
            return amount / 2 + (lootbox > 5 ether ? lootbox % 2.25 ether : 0);
        }
        if (_bafEthLeg(i)) return amount;
        return amount > 5 ether ? amount % 2.25 ether : 0;
    }

    /// @dev The reservation consolidation books: the ETH term of every position.
    function _bafReserve(uint256 pool) internal pure returns (uint256 reserve) {
        uint256 n = _bafPositions(pool);
        for (uint256 i; i < n; ++i) reserve += _bafEthTerm(pool, i);
    }

    /// @dev Whale half-passes award i queues when filled.
    function _bafHalves(uint256 pool, uint256 i) internal pure returns (uint256) {
        uint256 amount = _bafAmount(pool, i);
        uint256 ticketLeg = amount >= pool / 20 ? amount - amount / 2 : (_bafEthLeg(i) ? 0 : amount);
        return ticketLeg > 5 ether ? ticketLeg / 2.25 ether : 0;
    }

    /// @dev Arms the stage at `lvl` as consolidation would for `pool`.
    function _armBaf(uint24 lvl, uint256 pool, uint8 quadrant) internal {
        host.armBaf(lvl, uint128(pool), uint128(_bafReserve(pool)), quadrant, uint32(_bafPositions(pool)));
    }

    /// @dev The awards of the group at `start`, read from the views on the current state. A group
    ///      holds two scatter pairs (or the head awards) and the stage draws each pair when it
    ///      starts, so these are exact for the group's first pair, for trait pairs (the stage writes
    ///      no bucket) and for the head awards. A far-future second pair is drawn after the first
    ///      pair's ticket legs are queued and can differ from this read.
    function _groupWinners(uint24 lvl, uint256 word, uint256 start, uint256 pool)
        internal
        view
        returns (address[] memory w)
    {
        uint256 rounds = _bafRounds(pool);
        uint256 n = 2 * rounds + 3;
        uint256 end = start + BAF_GROUP > n ? n : start + BAF_GROUP;
        w = new address[](end - start);
        for (uint256 i = start; i < end; ++i) {
            if (i < 2 * rounds) {
                if (i & 3 == 0) {
                    address[4] memory pair = jackpots.bafPairWinners(lvl, word, i >> 2, rounds);
                    for (uint256 k; k < 4; ++k) w[i + k - start] = pair[k];
                }
            } else {
                w[i - start] = jackpots.bafHeadWinner(lvl, word, uint8(i - 2 * rounds));
            }
        }
    }

    /// @dev Appends award i's expected events in emission order.
    function _expectMarks(Mark[] memory m, uint256 n, address w, uint256 pool, uint256 i, uint24 floor)
        internal
        pure
        returns (uint256)
    {
        if (w == address(0)) return n;
        uint256 amount = _bafAmount(pool, i);
        uint256 ticketLeg;
        uint8 source;
        if (amount >= pool / 20) {
            m[n++] = Mark(ETH_SIG, w, amount / 2);
            ticketLeg = amount - amount / 2;
            source = WHALE_SRC_BAF_DIRECT;
        } else if (_bafEthLeg(i)) {
            m[n++] = Mark(ETH_SIG, w, amount);
        } else {
            ticketLeg = amount;
            source = WHALE_SRC_AWARD_TICKETS;
        }
        if (ticketLeg > 5 ether) {
            m[n++] = Mark(WHALE_SIG, w, ((ticketLeg / 2.25 ether) << 8) | source);
        } else if (ticketLeg != 0) {
            m[n++] = Mark(TICKET_SIG, w, floor);
            if (ticketLeg > 0.5 ether) m[n++] = Mark(TICKET_SIG, w, floor);
        }
        return n;
    }

    /// @dev The award events in `logs`, checking each one's fixed fields on the way.
    function _actualMarks(Vm.Log[] memory logs, uint24 lvl, uint24 floor) internal view returns (Mark[] memory m) {
        m = new Mark[](logs.length);
        uint256 n;
        for (uint256 j; j < logs.length; ++j) {
            Vm.Log memory l = logs[j];
            if (l.emitter != address(game) || l.topics.length == 0) continue;
            address who = l.topics.length > 1 ? address(uint160(uint256(l.topics[1]))) : address(0);
            if (l.topics[0] == ETH_SIG) {
                assertEq(uint256(l.topics[2]), lvl, "ETH leg level");
                assertEq(uint256(l.topics[3]), BAF_TRAIT_SENTINEL, "ETH leg sentinel");
                (uint256 amount,) = abi.decode(l.data, (uint256, uint256));
                m[n++] = Mark(ETH_SIG, who, amount);
            } else if (l.topics[0] == TICKET_SIG) {
                uint256 entryLevel = uint256(l.topics[2]);
                assertGe(entryLevel, floor, "no roll below the floor");
                assertLe(entryLevel, uint256(floor) + 50, "no roll beyond floor + 50");
                assertEq(uint256(l.topics[3]), BAF_TRAIT_SENTINEL, "roll sentinel");
                (, uint24 source,,) = abi.decode(l.data, (uint32, uint24, uint256, bool));
                m[n++] = Mark(TICKET_SIG, who, source);
            } else if (l.topics[0] == WHALE_SIG) {
                (uint256 halves, uint8 source) = abi.decode(l.data, (uint256, uint8));
                m[n++] = Mark(WHALE_SIG, who, (halves << 8) | source);
            }
        }
        assembly ("memory-safe") { mstore(m, n) }
    }

    function _assertMarks(Mark[] memory actual, Mark[] memory expected, uint256 n) internal pure {
        assertEq(actual.length, n, "award event count");
        for (uint256 k; k < n; ++k) {
            assertEq(actual[k].sig, expected[k].sig, "award event kind");
            assertEq(actual[k].who, expected[k].who, "award event winner");
            assertEq(actual[k].value, expected[k].value, "award event value");
        }
    }

    /// @dev The ETH credited to claimable in `logs` (every credit the stage makes emits one).
    function _creditedIn(Vm.Log[] memory logs) internal view returns (uint256 total) {
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
            if (logs[j].topics[0] != CREDIT_SIG) continue;
            total += abi.decode(logs[j].data, (uint256));
        }
    }

    /// @dev Advance(19) markers in `logs`; any other stage fails.
    function _bafStageMarkers(Vm.Log[] memory logs, uint24 lvl) internal view returns (uint256 count) {
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
            if (logs[j].topics[0] != ADVANCE_SIG) continue;
            (uint8 stage, uint24 at) = abi.decode(logs[j].data, (uint8, uint24));
            assertEq(stage, STAGE_BAF, "the award stage reports itself");
            assertEq(at, lvl);
            ++count;
        }
    }

    /// @dev `bafLevel[lvl]` and the four `bafTop[lvl]` slots in DegenerusJackpots.
    function _bracketBoard(uint24 lvl) internal view returns (uint64 epoch, uint8 topLen, bool skipped, uint256 topBits) {
        uint256 packed = uint256(vm.load(address(jackpots), keccak256(abi.encode(uint256(lvl), uint256(2)))));
        epoch = uint64(packed);
        topLen = uint8(packed >> 64);
        skipped = uint8(packed >> 72) != 0;
        uint256 base = uint256(keccak256(abi.encode(uint256(lvl), uint256(1))));
        for (uint256 i; i < 4; ++i) topBits |= uint256(vm.load(address(jackpots), bytes32(base + i)));
    }
}
