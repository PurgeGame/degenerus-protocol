// SPDX-License-Identifier: AGPL-3.0-only
import {sDGNRS} from "../../contracts/sDGNRS.sol";

pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {ICoinflip} from "../../contracts/interfaces/ICoinflip.sol";
import {IDegenerusGame} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "../../contracts/interfaces/IDegenerusJackpots.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {FreshWordLeg} from "./PurchaseDailyWorstCase.t.sol";
import {ProtocolBoonDrawSeeder} from "./helpers/ProtocolBoonDrawSeeder.sol";
import {VaultHistorySeeder} from "./AdvanceNestedSettlementGas.t.sol";
import {BafDrawSeed} from "../helpers/BafDrawSeed.sol";
import {BafViews} from "../helpers/BafViews.sol";
import {BafBoardSeed} from "../helpers/BafBoardSeed.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {CrapsSlots} from "../helpers/GameSlots.sol";

/// @dev The level-100 BAF award schedule and its award events. With R scatter rounds (48 below a
///      500 ETH pool) positions 0..2R-1 are the rounds in (best, second) pairs, a round pair's four
///      positions drawn together when the pair starts; 2R..2R+2 are the head awards (top bettor
///      P/10, armed-day depositor draw P/20, word-picked third or fourth place P/20).
library BafSchedule {
    uint256 internal constant ROUNDS = 48;
    uint256 internal constant POSITIONS = 2 * ROUNDS + 3;
    uint256 internal constant GROUP = 8;
    uint24 internal constant LVL = 100;
    uint256 private constant HALF_PASS = 2.25 ether;
    uint256 private constant CLAIM_THRESHOLD = 5 ether;
    uint256 private constant SMALL_THRESHOLD = 0.5 ether;
    uint256 private constant TRAIT_SENTINEL = 420;
    bytes32 internal constant ETH_SIG = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_SIG =
        keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant WHALE_SIG = keccak256("JackpotWhalePassWin(uint32,uint256,uint8)");

    /// @dev One award event: signature, recipient wallet ID, the ETH amount (ETH credit) or half-pass count
    ///      (whale pass), zero for a ticket roll; `level` and `entries` are a ticket roll's target
    ///      level and queued entries.
    struct Award {
        bytes32 sig;
        uint32 winner;
        uint256 value;
        uint256 level;
        uint256 entries;
    }

    function amount(uint256 pool, uint256 i) internal pure returns (uint256) {
        return amountR(pool, i, ROUNDS);
    }

    function amountR(uint256 pool, uint256 i, uint256 rounds) internal pure returns (uint256) {
        if (i < 2 * rounds) return i & 1 == 0 ? (pool / 2) / rounds : ((pool * 30) / 100) / rounds;
        return i == 2 * rounds ? pool / 10 : pool / 20;
    }

    /// @dev A small scatter award pays ETH for the best of an even round and the second of an odd round.
    function ethLeg(uint256 i) internal pure returns (bool) {
        return ((i >> 1) ^ i) & 1 == 0;
    }

    /// @dev The ETH an award at position `i` credits to claimable when filled.
    function ethTerm(uint256 pool, uint256 i) internal pure returns (uint256) {
        return ethTermR(pool, i, ROUNDS);
    }

    function ethTermR(uint256 pool, uint256 i, uint256 rounds) internal pure returns (uint256) {
        uint256 a = amountR(pool, i, rounds);
        if (a >= pool / 20) {
            uint256 half = a - a / 2;
            return a / 2 + (half > CLAIM_THRESHOLD ? half % HALF_PASS : 0);
        }
        if (ethLeg(i)) return a;
        return a > CLAIM_THRESHOLD ? a % HALF_PASS : 0;
    }

    /// @dev Positions `from`..`to` - 1 summed: the reservation when the range is the whole schedule.
    function ethTerms(uint256 pool, uint256 from, uint256 to) internal pure returns (uint256 total) {
        return ethTermsR(pool, from, to, ROUNDS);
    }

    function ethTermsR(uint256 pool, uint256 from, uint256 to, uint256 rounds) internal pure returns (uint256 total) {
        for (uint256 i = from; i < to; ++i) total += ethTermR(pool, i, rounds);
    }

    /// @dev Appends the award events position `i` emits for `winner` to `out` from index `n`.
    function expect(Award[] memory out, uint256 n, uint256 pool, uint256 i, uint32 winner)
        internal
        pure
        returns (uint256 next, uint256 rolls, uint256 whales)
    {
        return expectR(out, n, pool, i, winner, ROUNDS);
    }

    function expectR(Award[] memory out, uint256 n, uint256 pool, uint256 i, uint32 winner, uint256 rounds)
        internal
        pure
        returns (uint256 next, uint256 rolls, uint256 whales)
    {
        next = n;
        if (winner == 0) return (next, 0, 0);
        uint256 a = amountR(pool, i, rounds);
        uint256 lootbox = a;
        if (a >= pool / 20) {
            out[next++] = Award(ETH_SIG, winner, a / 2, 0, 0);
            lootbox = a - a / 2;
        } else if (ethLeg(i)) {
            out[next++] = Award(ETH_SIG, winner, a, 0, 0);
            return (next, 0, 0);
        }
        if (lootbox > CLAIM_THRESHOLD) {
            out[next++] = Award(WHALE_SIG, winner, lootbox / HALF_PASS, 0, 0);
            return (next, 0, 1);
        }
        rolls = lootbox <= SMALL_THRESHOLD ? 1 : 2;
        for (uint256 k; k < rolls; ++k) out[next++] = Award(TICKET_SIG, winner, 0, 0, 0);
    }

    /// @dev The award events among `logs` in emission order. `tagged` is false when an ETH or
    ///      ticket event lacks the BAF trait sentinel or an ETH event names another level.
    function awardsOf(Vm.Log[] memory logs) internal pure returns (Award[] memory out, bool tagged) {
        out = new Award[](logs.length);
        tagged = true;
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 != ETH_SIG && t0 != TICKET_SIG && t0 != WHALE_SIG) continue;
            uint32 who = uint32(uint256(logs[i].topics[1]));
            uint256 value;
            uint256 entryLevel;
            uint256 entries;
            if (t0 == TICKET_SIG) {
                entryLevel = uint256(logs[i].topics[2]);
                (uint32 queued,,,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
                entries = queued;
            }
            if (t0 == ETH_SIG) {
                (value,) = abi.decode(logs[i].data, (uint256, uint256));
                if (uint256(logs[i].topics[2]) != LVL) tagged = false;
            } else if (t0 == WHALE_SIG) {
                (value,) = abi.decode(logs[i].data, (uint256, uint8));
            }
            if (t0 != WHALE_SIG && uint256(logs[i].topics[3]) != TRAIT_SENTINEL) tagged = false;
            out[n++] = Award(t0, who, value, entryLevel, entries);
        }
        assembly ("memory-safe") {
            mstore(out, n)
        }
    }

    /// @dev Walks one group's award events (`got`, positions `from`..`to` - 1) position by position:
    ///      each position must pay `expected` (the bracket views' draw on the state its pair starts
    ///      from, `BafPairDraw`) the schedule's amount and leg; the winners are recorded in `paid`.
    function checkGroup(
        Award[] memory got,
        uint256 pool,
        uint256 from,
        uint256 to,
        uint32[] memory expected,
        uint32[] memory paid
    ) internal pure returns (uint256 credited) {
        return checkGroupR(got, pool, from, to, expected, paid, ROUNDS);
    }

    function checkGroupR(
        Award[] memory got,
        uint256 pool,
        uint256 from,
        uint256 to,
        uint32[] memory expected,
        uint32[] memory paid,
        uint256 rounds
    ) internal pure returns (uint256 credited) {
        Award[] memory want = new Award[](3);
        uint256 ptr;
        for (uint256 i = from; i < to; ++i) {
            require(ptr < got.length, "every position of the group pays");
            uint32 winner = got[ptr].winner;
            require(winner != 0, "every position has a winner");
            require(winner == expected[i - from], "the group pays the views' draw at the pair start");
            (uint256 n,,) = expectR(want, 0, pool, i, winner, rounds);
            require(ptr + n <= got.length, "every award of the position pays");
            for (uint256 k; k < n; ++k) {
                Award memory a = got[ptr + k];
                require(
                    a.sig == want[k].sig && a.winner == winner && a.value == want[k].value,
                    "the position's awards follow the schedule"
                );
            }
            ptr += n;
            credited += ethTermR(pool, i, rounds);
            paid[i - from] = winner;
        }
        require(ptr == got.length, "no award beyond the group");
    }

    /// @dev Extends `digest` with every award event in `logs` (topics and data), so the award
    ///      stream of a partition can be compared with any other partition's.
    function chain(bytes32 digest, Vm.Log[] memory logs) internal pure returns (bytes32) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == ETH_SIG || t0 == TICKET_SIG || t0 == WHALE_SIG) {
                digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
            }
        }
        return digest;
    }
}

/// @dev A game host's reference seam: the production queue sink with one logged ticket roll's
///      arguments.
interface IBafReplayHost {
    function replayQueuedId(uint32 id, uint24 targetLevel, uint32 entries) external;
}

/// @dev Reference draw of one award group of the level-100 bracket under the stage's rule: a round
///      pair's four awards are drawn by `bafPairWinners` when the pair starts.
library BafPairDraw {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev On the current state, the group's start (snapshot `pre`), draws positions `from`..`to` - 1
    ///      two ways. `atStart` draws every pair of the group on that state. `atPair` draws each pair
    ///      on the state it starts from in the stage: the group-start state plus the queue writes of
    ///      the group's earlier ticket rolls (`got`, the award events of a run of the same group),
    ///      replayed through the production queue sink. The head awards read only the board and the
    ///      depositor book. Restores `pre` before returning.
    function draw(
        address jackpots,
        address host,
        uint256 pre,
        BafSchedule.Award[] memory got,
        uint256 pool,
        uint256 word,
        uint256 from,
        uint256 to,
        uint256 rounds
    ) internal returns (uint32[] memory atStart, uint32[] memory atPair) {
        require(from >= 2 * rounds || from & 3 == 0, "a group starts at a pair boundary");
        IDegenerusJackpots views = IDegenerusJackpots(jackpots);
        atStart = new uint32[](to - from);
        atPair = new uint32[](to - from);
        uint32[4] memory w;
        for (uint256 i = from; i < to; ++i) {
            if (i < 2 * rounds) {
                if (i & 3 == 0) w = BafViews.pair(address(views), BafSchedule.LVL, word, i >> 2, rounds);
                atStart[i - from] = w[i & 3];
            } else {
                atStart[i - from] = views.bafHeadWinner(BafSchedule.LVL, word, uint8(i - 2 * rounds));
            }
        }
        BafSchedule.Award[] memory want = new BafSchedule.Award[](3);
        uint256 ptr;
        for (uint256 i = from; i < to; ++i) {
            if (i < 2 * rounds) {
                if (i & 3 == 0) w = BafViews.pair(address(views), BafSchedule.LVL, word, i >> 2, rounds);
                atPair[i - from] = w[i & 3];
            } else {
                atPair[i - from] = atStart[i - from];
            }
            (uint256 n,,) = BafSchedule.expectR(want, 0, pool, i, atPair[i - from], rounds);
            for (uint256 k; k < n && ptr < got.length; ++k) {
                BafSchedule.Award memory a = got[ptr++];
                if (a.sig == BafSchedule.TICKET_SIG) {
                    IBafReplayHost(host).replayQueuedId(a.winner, uint24(a.level), uint32(a.entries));
                }
            }
        }
        VM.revertToState(pre);
    }
}

/// @dev The century bracket's BAF state. Every wallet the scatter rounds can sample qualifies: the
///      trait-bucket holders the seeder places for the minted-level rounds and every far-future
///      queue holder get a distinct positive score, written to DegenerusJackpots storage directly
///      (`bafPlayer` slot 0, `bafTop` slot 1, `bafLevel` slot 2). Four large bettors fill the head
///      board, and one depositor fills the armed day's draw book.
library CenturyBafScores {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant LVL = 100;

    function levelWord(address jackpots) internal view returns (uint256) {
        return uint256(VM.load(jackpots, keccak256(abi.encode(LVL, uint256(2)))));
    }

    function topEntry(address jackpots, uint256 i) internal view returns (uint256) {
        return uint256(VM.load(jackpots, bytes32(uint256(keccak256(abi.encode(LVL, uint256(1)))) + i)));
    }

    /// @dev Scores the seeder's trait-bucket holders (round r: 0xC3700000 + r * 4096 + 1..2048)
    ///      and far-future holders (levels 102..105: 0xFA000000 + 0..8191; levels 106..199:
    ///      0xFB000000 + 0..12031) at the bracket's current epoch, for the 48-round schedule.
    function seedCandidates(address jackpots, address game) internal {
        seedCandidatesR(jackpots, game, 24, 1);
    }

    /// @dev As `seedCandidates`, for a schedule whose minted-level rounds are 0..`traitRounds` - 1
    ///      and far-future queues `depth` times as deep (see `CenturyConsolidationSeeder.seedRounds`).
    function seedCandidatesR(address jackpots, address game, uint256 traitRounds, uint256 depth) internal {
        uint256 epochBits = uint256(uint64(levelWord(jackpots))) << 192;
        bytes32 bracket = keccak256(abi.encode(LVL, uint256(0)));
        for (uint256 r; r < traitRounds; ++r) {
            uint256 first = 0xC3700000 + r * 4096 + 1;
            for (uint256 k; k < 2048; ++k) _score(jackpots, game, bracket, first + k, epochBits);
        }
        for (uint256 k; k < 4 * 2048 * depth; ++k) _score(jackpots, game, bracket, 0xFA000000 + k, epochBits);
        for (uint256 k; k < 94 * 128 * depth; ++k) _score(jackpots, game, bracket, 0xFB000000 + k, epochBits);
    }

    /// @dev Head board 0xBAF000..0xBAF003 (1M..4M FLIP) and a 4096-interval draw book of one
    ///      depositor armed for `day`, so the depositor draw walks a cold 12-step binary search.
    function seedHead(address jackpots, address coinflip, address game, uint24 day) internal {
        for (uint256 i; i < 4; ++i) {
            uint32 id = _register(game, address(uint160(0xBAF000 + i)));
            VM.prank(ContractAddresses.COINFLIP);
            IDegenerusJackpots(jackpots).recordBafFlip(id, uint24(LVL), (i + 1) * 1_000_000 ether);
        }
        uint256 depositorId = _register(game, address(0xD3F0517));
        for (uint256 i; i < 4096; ++i) {
            BafDrawSeed.entry(coinflip, day, uint32(i), uint32(depositorId), uint96((i + 1) * 100));
        }
        VM.store(coinflip, keccak256(abi.encode(uint256(day), uint256(5))), bytes32((uint256(4096) << 96) | 409_600));
        VM.prank(game);
        ICoinflip(coinflip).armBafDraw(day);
    }

    function _register(address game, address wallet) private returns (uint32 id) {
        VM.prank(ContractAddresses.AFFILIATE);
        id = IDegenerusGame(game).registerWallet(wallet, true);
    }

    function _score(address jackpots, address game, bytes32 bracket, uint256 who, uint256 epochBits) private {
        uint256 id = IDegenerusGame(game).walletIdOf(address(uint160(who)));
        VM.store(jackpots, keccak256(abi.encode(id, bracket)), bytes32(epochBits | (100 ether + (who % 1009) * 1 ether)));
    }
}

/// @dev Controlled, committed resolver state, not a replay of the first 99 levels.
///      Production bytecode is restored before the real request and measured advance.
contract CenturyConsolidationSeeder is DegenerusGame, BucketSeed {
    /// @dev The century state for the 48-round schedule (pools below 500 ETH).
    function seed(uint256 word, uint128 nextPool, uint128 futurePool) external {
        seedRounds(word, nextPool, futurePool, 48);
    }

    /// @dev The century state with the minted-level buckets of a `rounds`-round schedule seeded. Above
    ///      48 rounds the far-future queues are four times as deep, so the doubled samples still
    ///      draw distinct wallets.
    function seedRounds(uint256 word, uint128 nextPool, uint128 futurePool, uint256 rounds) public {
        uint24 day = _simulatedDayIndex();
        level = 99;
        // Real maximum supply, with prior transition coverage committed.
        for (uint256 i = _deityCount(); i < 32; ++i) {
            _seedDeity(address(uint160(0xDE170000 + i)));
        }
        purchaseStartDay = day - 8; // accelerated skim trough; preserve the fixture's minimum-rate shape
        dailyIdx = day - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        _setDecWindowOpen(true);
        currentPrizePool = 0;
        _setPrizePools(nextPool, futurePool);
        levelPrizePool[98] = (uint256(nextPool) * 8) / 10;
        levelPrizePool[99] = (uint256(nextPool) * 9) / 10;
        // Seed + 23 ETH surplus share + the 1% insurance skim of nextPool reaches the x00
        // dump, whose 40% must move the 17 ETH (+ a quarter of the skim) the pinned
        // BAF pools were tuned for.
        yieldAccumulator = 18.25 ether + uint256(nextPool) / 400;

        // The synthetic jump skips the bootstrap cohorts at levels 2..100.
        // Retire only their physical queue headers before binding the century's
        // separately seeded population; production never discards a live queue.
        for (uint24 oldLevel = 1; oldLevel <= 100; ++oldLevel) {
            uint256[] storage oldQueue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(oldQueue.slot, 0) }
        }

        // Perpetual tickets populate every BAF candidate level in a live game. The far-future
        // scatter bands sample lvl+2..lvl+5 (102..105, revisited by every round pair of its band)
        // and lvl+6..lvl+99 (106..199). Holders are wholly synthetic (not the SDGNRS/VAULT
        // deities, which would repeat identically across all 98 levels) and keyed by (level,
        // slot index), so every lane holds a different wallet. Band 2's levels get a deep pool
        // (2048) and band 3's 128; both exceed the sampler's 8-lane window, and both are
        // multiples of eight, so a BAF winner's first ticket roll onto a level starts a fresh
        // queue word.
        uint256 depth = farDepth(rounds);
        for (uint24 target = 102; target <= 105; ++target) {
            for (uint256 i; i < 2048 * depth; ++i) {
                address p = address(uint160(0xFA000000 + (uint256(target) - 102) * 2048 * depth + i));
                _seedQueued(_tqFarFutureKey(target), target, p, uint80(4 << 8));
            }
        }
        for (uint24 target = 106; target <= 199; ++target) {
            for (uint256 i; i < 128 * depth; ++i) {
                address p = address(uint160(0xFB000000 + (uint256(target) - 106) * 128 * depth + i));
                _seedQueued(_tqFarFutureKey(target), target, p, uint80(4 << 8));
            }
        }

        // The minted-level scatter rounds (rounds / 4 at level 100, then rounds / 4 at level 101;
        // 12 and 12 for 48 rounds) each read four
        // entries of one packed word of the (level, trait) bucket that hash2(base, round) selects,
        // base = hash2(word, BAF tag). Each selected bucket holds 2048 distinct wallets; a bucket
        // selected by two rounds keeps the first round's wallets (for the fixture's words such
        // rounds read different packed words, so no wallet is a candidate twice).
        uint256 board = BafBoardSeed.context(100, word, rounds);
        for (uint256 round; round < rounds / 2; ++round) {
            uint24 target = round < rounds / 4 ? 100 : 101;
            uint8 trait = uint8(uint32(board) >> ((round % 4) * 8));
            if (_seedBucketLen(target, trait) < 2048) {
                _seedBucketDistinct(target, trait, 2048, uint160(0xC3700000 + round * 4096));
            }
        }
        // Sealing is constant work regardless of the entrant population.
        decBattleRounds[100].count = 1_000_000;
    }

    /// @dev Far-future queue depth multiplier of a `rounds`-round schedule.
    function farDepth(uint256 rounds) public pure returns (uint256) {
        return rounds > 48 ? 4 : 1;
    }
}

/// @dev Complete production facade plus exact native worker seams. The seams do
/// not seed progress or replace any production work inside the measured phase.
contract CenturyNativeGasHost is DegenerusGame, WalletSeed {
    function publishOnly() external {
        _native(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng()"));
    }
    function prepareTicketsOnly() external returns (bool done) {
        MineFlipGas.Result memory result = abi.decode(_native(ContractAddresses.GAME_TICKET_MODULE,
            abi.encodeWithSignature("runTicketWork(uint24,uint256)", level, uint256(9_000_000))),
            (MineFlipGas.Result));
        done = result.done;
        if (done) {
            // Identical normalization to Miner after a completed native read.
            ticketsFullyProcessed = true;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        }
    }
    function applyOnly() external {
        _native(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord()"));
    }
    function dailyOnly() external returns (MineFlipGas.Result memory) {
        return dailyWith(9_000_000);
    }
    function dailyWith(uint256 allowance) public returns (MineFlipGas.Result memory) {
        return abi.decode(_native(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeWithSignature("runDailyPhase(uint256)", allowance)), (MineFlipGas.Result));
    }
    function bafWork() external view returns (uint8 kind, uint16 cursor, uint32 count, uint128 reserved) {
        JackpotWork storage work = jackpotWork;
        return (work.kind, work.winner, work.traits, work.paid);
    }
    function bafPool() external view returns (uint256) {
        return jackpotWork.budget;
    }
    /// @dev claimablePool, futurePool and the pending future share a frozen pool accumulates.
    function poolsProbe() external view returns (uint256 claimable, uint256 future, uint256 pendingFuture) {
        (, uint128 pending) = _getPendingPools();
        return (claimablePool, _getFuturePrizePool(), pending);
    }
    /// @dev Reference seam: the production queue sink with one logged ticket roll's arguments.
    function replayQueuedId(uint32 id, uint24 targetLevel, uint32 entries) external {
        _queueEntries(id, targetLevel, entries, true);
    }
    function _native(address target, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory reason) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        return reason;
    }
}

abstract contract CenturyConsolidationFixture is FreshWordLeg {
    uint256 internal constant CAP = 10_000_000;
    uint8 internal constant STAGE_PURCHASE_BATTLE = 17;
    uint8 internal constant STAGE_ENTERED_JACKPOT = 7;
    uint8 internal constant STAGE_JACKPOT_BAF_AWARDS = 19;
    uint256 internal constant BAF_GROUP = BafSchedule.GROUP;
    /// @dev Admits exactly one award group per call: the group bound, its tail, the phase tail and
    ///      check reserve, plus the runDailyPhase preamble and module hops before the group check.
    uint256 internal constant ONE_GROUP_ALLOWANCE = GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL
        + GasBounds.DAILY_PHASE_TAIL + MineFlipGas.CHECK_RESERVE + 100_000;
    /// @dev The allowance the native daily phase runs at elsewhere in this fixture.
    uint256 internal constant COMPOSED_ALLOWANCE = 9_000_000;
    uint256 internal constant WORD = 0x0ee7fcb287531227df7efcfddb3f0151121ee9e59765e743a190d8e26ee417fd;
    bytes32 internal constant ETH_SIG = BafSchedule.ETH_SIG;
    bytes32 internal constant TICKET_SIG = BafSchedule.TICKET_SIG;
    bytes32 internal constant WHALE_SIG = BafSchedule.WHALE_SIG;

    struct Shape {
        uint128 nextPool;
        uint128 futurePool;
        uint256 bafPool;
        uint256 ticketRolls;
        uint256 whaleAwards;
        bool housePass;
    }

    struct Tally {
        uint256 ethAwards;
        uint256 ticketAwards;
        uint256 whaleAwards;
        uint256 decimator;
        uint256 yieldEvents;
        uint256 growth;
        uint256 quest;
        uint256 highPasses;
        uint256 distinct;
        uint256 distinctTicketPairs;
        uint256 farRolls;
        bytes32[] ticketPairs;
        uint32[] recipients;
    }

    /// @dev Award-stage measurement: per-group cold gas, the composed run, and draw bookkeeping.
    struct StageRun {
        uint256[] groupGas;
        uint256 groupSum;
        uint256 worst;
        uint256 worstGroup;
        uint256 redrawn;
        uint256 moved;
        bytes32 digest;
    }

    uint256 private expectedPool;
    uint256 private expectedRolls;
    uint256 private expectedWhales;
    bool private expectHousePass;
    /// @dev Every position's winner drawn by the bracket views before the consolidation.
    uint32[] private predicted;
    /// @dev The pool's scatter round count (the draw module's `_bafRounds`) and award positions.
    uint256 internal rounds;
    uint256 internal positions;

    function _shape() internal pure virtual returns (Shape memory);

    function _rngWord() internal pure virtual returns (uint256) {
        return WORD;
    }

    /// @dev 0 = steady state, 1 = historical claim commits, 2 = funding fails and rolls back.
    function _vaultHistoryMode() internal pure virtual returns (uint8) {
        return 0;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        Shape memory s = _shape();
        uint256 word = _rngWord();
        expectedPool = s.bafPool;
        expectedRolls = s.ticketRolls;
        expectedWhales = s.whaleAwards;
        expectHousePass = s.housePass;
        bytes memory original = address(game).code;
        vm.etch(address(game), type(CenturyConsolidationSeeder).runtimeCode);
        rounds = _bafRounds(s.bafPool);
        positions = 2 * rounds + 3;
        CenturyConsolidationSeeder(payable(address(game))).seedRounds(word, s.nextPool, s.futurePool, rounds);
        vm.etch(address(game), original);
        // Total obligations + 100 ETH of actual surplus. Nonzero stETH forces the
        // mock's full shares-based balanceOf path rather than its empty fast path.
        vm.deal(address(game), uint256(s.nextPool) + s.futurePool + 68.25 ether + uint256(s.nextPool) / 400);
        mockStETH.mint(address(game), 50 ether);
        _armCenturyWord(word, 400);
        assertEq(game.level(), 100, "real request must pre-increment the level");
        assertEq(game.rngWordForDay(400), 0, "the word-apply transaction must apply fresh RNG");
        assertFalse(game.decWindow(), "real century request closes the burn window");

        CenturyBafScores.seedCandidatesR(address(jackpots), address(game), rounds / 2, rounds > 48 ? 4 : 1);
        CenturyBafScores.seedHead(address(jackpots), address(coinflip), address(game), 400);
        assertEq(uint8(CenturyBafScores.levelWord(address(jackpots)) >> 64), 4, "bafLevel layout: four board entries");
        (, uint96 weight, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 4096, "draw layout must match source");
        assertEq(weight, 409_600, "draw intervals must fill its header");

        // A real closed batch remains unresolved until the later redemption consumer stage.
        vm.deal(address(sdgnrs), 10_000 ether);
        uint256 burn = sdgnrs.totalSupply() / 1000;
        address burner = address(0xCE470);
        _giveWalletId(burner); // reward recipients are game players with wallet IDs
        vm.prank(address(game)); sdgnrs.transferFromPool(sDGNRS.Pool.Reward, burner, burn);
        vm.prank(burner); sdgnrs.burn(burn);
        uint256 claimable = game.claimableWinningsOf(address(sdgnrs));
        vm.prank(address(game)); sdgnrs.closeRedemptionBatch(claimable);
        (,uint32 settling,,) = sdgnrs.redemptionBatchState();
        assertGt(settling, 0);
        assertGt(sdgnrs.pendingRedemptionEthValue(), 0);

        uint8 historyMode = _vaultHistoryMode();
        if (historyMode != 0) {
            original = address(coinflip).code;
            vm.etch(address(coinflip), type(VaultHistorySeeder).runtimeCode);
            VaultHistorySeeder(address(coinflip)).seedVaultHistory(historyMode == 1);
            vm.etch(address(coinflip), original);
            vm.store(address(crapsBattle), keccak256(abi.encode(uint256(1), CrapsSlots.PASS_CREDITS_BY_ID)), bytes32(0));
            vm.store(address(coin), bytes32(0), bytes32(uint256(uint128(uint256(vm.load(address(coin), bytes32(0)))))));
        }
        _predictAwards(word, s);
    }

    /// @dev Draws every position with the bracket views (scores are frozen from here on) and
    ///      derives the expected award counts from the schedule's amounts and legs: every position
    ///      must hold a qualifying, distinct winner.
    function _predictAwards(uint256 word, Shape memory s) private {
        uint32[] memory drawn = new uint32[](positions);
        for (uint256 r; r < rounds; ++r) {
            (drawn[2 * r], drawn[2 * r + 1]) = BafViews.round(address(jackpots), 100, word, r, rounds);
        }
        for (uint8 slot; slot < 3; ++slot) drawn[2 * rounds + slot] = jackpots.bafHeadWinner(100, word, slot);
        BafSchedule.Award[] memory buf = new BafSchedule.Award[](3);
        uint256 ethCount;
        uint256 rolls;
        uint256 whales;
        for (uint256 i; i < positions; ++i) {
            require(drawn[i] != 0, "every BAF position must have a qualifying winner");
            for (uint256 j; j < i; ++j) {
                require(drawn[i] != drawn[j], "BAF recipients must be distinct");
            }
            (, uint256 r_, uint256 w_) = BafSchedule.expectR(buf, 0, s.bafPool, i, drawn[i], rounds);
            if (buf[0].sig == ETH_SIG) ++ethCount;
            rolls += r_;
            whales += w_;
            predicted.push(drawn[i]);
        }
        // The three head awards always clear the P/20 floor and the 2R scatter awards never do;
        // half the scatter awards take the ETH leg: 3 + R.
        require(
            ethCount == rounds + 3 && rolls == s.ticketRolls && whales == s.whaleAwards, "shape threshold prediction"
        );
    }

    /// @dev The draw module's round count: 48 below 500 ETH, doubled at each fourfold step from
    ///      there, at most 1,536.
    function _bafRounds(uint256 pool) internal pure returns (uint256 r) {
        r = 48;
        for (uint256 step = 500 ether; r < 1536 && pool >= step; step *= 4) r *= 2;
    }

    function _armCenturyWord(uint256 word, uint24 day) private {
        for (uint24 i = 1; i <= 7; ++i) {
            vm.store(address(crapsBattle), keccak256(abi.encode(uint256(day - i), CRAPS_DAY_STAKED_SLOT)),
                bytes32((uint256(500_000 ether) << 128) | uint256(1_000_000 ether)));
        }
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, uint256(keccak256("yesterday")) | 1, day - 1);
        uint256 beforeRequest = mockVRF.lastRequestId();
        // A synthetic day-400 jump leaves real day-2 table housekeeping ahead
        // of a fresh request. Drive that ordered work instead of assuming the
        // very first mineFlip can skip directly to the request.
        for (uint256 calls; mockVRF.lastRequestId() == beforeRequest; ++calls) {
            assertLt(calls, 512, "century request preparation stalled");
            game.mineFlip{gas: 12_000_000}();
        }
        assertEq(mockVRF.lastRequestId(), beforeRequest + 1, "one real daily request");
        mockVRF.fulfillRandomWords(beforeRequest + 1, word);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ProtocolBoonDrawSeeder).runtimeCode);
        ProtocolBoonDrawSeeder(address(game)).seedPools(day, word);
        vm.etch(address(game), original);
    }

    /// @dev The real miner composes every admitted checkpoint into a call, so a whole call is not
    ///      bounded (owner rule: one admitted chunk is the unit; IsolatedColdChunks below pins each
    ///      native chunk against its declared bound). Here the composed miner call is driven at the
    ///      realistic 10M allowance and at the 16.7M ceiling: each must succeed and make progress
    ///      at the word application and at the consolidation, and its gas is logged.
    function test_CenturyConsolidationFullColdTransaction() public {
        // No protocol reads before each call: setUp writes are committed, all accessed storage
        // starts cold, and original-vs-current SSTORE pricing is realistic.
        vm.etch(address(game), type(CenturyNativeGasHost).runtimeCode);
        _checkWordApply(true);
        _driveNativeBattle();
        _checkRealisticMinerCalls("century_composed_miner_including_intrinsic");
        _checkConsolidation(true);
    }

    /// @dev From a snapshot, one real mineFlip at 10M and one at 16.7M: each succeeds and
    ///      progresses (emits a stage marker); state is restored after each.
    function _checkRealisticMinerCalls(string memory label) private {
        uint256[2] memory allowances = [uint256(CAP), 16_700_000];
        for (uint256 a; a < allowances.length; ++a) {
            uint256 snapshot = vm.snapshotState();
            vm.recordLogs();
            (bool ok,) = address(game).call{gas: allowances[a]}(abi.encodeWithSignature("mineFlip()"));
            uint256 used = vm.lastCallGas().gasTotalUsed;
            if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
            assertTrue(ok, "a realistic miner allowance succeeds");
            assertGt(_countTopic(vm.getRecordedLogs(), keccak256("Advance(uint8,uint24)")), 0, "and makes progress");
            emit log_named_uint(string.concat(label, a == 0 ? "_at_10M" : "_at_16_7M"), used);
            vm.revertToState(snapshot);
        }
    }

    /// @dev Measure the native chunks without imposing a 10M cap on a transaction
    /// that may legitimately compose several separately admitted chunks.
    function test_CenturyConsolidationIsolatedColdChunks() public {
        vm.etch(address(game), type(CenturyNativeGasHost).runtimeCode);
        _checkWordApply(false);
        _driveNativeBattle();
        _checkConsolidation(false);
    }

    /// @dev The fresh word applies alone: the day's RNG record (redemption stays pending), the
    ///      craps day it opens and, in the history variants, the vault's 365-day claim.
    function _checkWordApply(bool measureComposition) private {
        uint8 historyMode = _vaultHistoryMode();
        if (historyMode != 0) {
            // This post-walk loss mint is observable even when later seat funding
            // reverts; a rolled-back cursor alone would not exclude an early failure.
            vm.expectCall(
                ContractAddresses.WWXRP,
                abi.encodeWithSignature("creditPrize(uint32,uint256)", uint32(1), 1)
            );
        }
        CenturyNativeGasHost host = CenturyNativeGasHost(payable(address(game)));
        host.publishOnly();
        uint256 reads;
        while (!host.prepareTicketsOnly{gas: 12_000_000}()) {
            assertLt(++reads, 32, "century ticket prerequisites stalled");
        }
        if (measureComposition) _checkRealisticMinerCalls("century_composed_daily_apply_including_intrinsic");
        vm.recordLogs();
        host.applyOnly{gas: 12_000_000}();
        uint256 used = _coldCallGas();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertLt(used, GasBounds.DAILY_APPLY, "century daily apply exceeds saved bound");
        assertEq(_dailyLegLogs(logs), 0, "native application cannot pay a daily leg");
        emit log_named_uint("century_word_apply_including_intrinsic", used);
        assertEq(
            _countTopic(logs, keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)")),
            1,
            "fresh RNG must apply in the word-apply call"
        );
        assertEq(_countTopic(logs, keccak256("RedemptionResolved(uint32,uint16,uint16)")), 0, "redemption resolves only after daily work");
        if (historyMode != 0) {
            bytes32 stateSlot = keccak256(abi.encode(uint32(1), uint256(2)));
            uint24 cursor = uint24(uint256(vm.load(address(coinflip), stateSlot)) >> 128);
            emit log_named_uint("vault_claim_cursor_after", cursor);
            assertEq(cursor, historyMode == 1 ? 399 : 34, "365-day settlement must commit or roll back");
        }
    }

    function _coldCallGas() private returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
    }

    function _nativePhaseTx() private returns (uint8 stage, uint256 used, Vm.Log[] memory logs) {
        vm.recordLogs();
        MineFlipGas.Result memory result = CenturyNativeGasHost(payable(address(game))).dailyOnly{gas: 12_000_000}();
        used = _coldCallGas();
        logs = vm.getRecordedLogs();
        assertTrue(result.progressed, "native daily phase must make progress");
        stage = _lastStage(logs);
    }

    function _driveNativeBattle() private {
        IJackpotBattle battle = IJackpotBattle(address(crapsBattle));
        (,,, bool complete) = battle.jackpotProgress();
        uint256 steps;
        uint256 largest;
        while (!complete) {
            assertLt(steps++, 40, "the native jackpot battle stalled");
            (uint8 stage, uint256 used, Vm.Log[] memory logs) = _nativePhaseTx();
            assertEq(stage, STAGE_PURCHASE_BATTLE, "committed battle precedes consolidation");
            assertEq(_dailyLegLogs(logs), 0, "battle cannot execute consolidation payouts");
            assertLe(used, CAP, "native battle transaction exceeds 10M");
            if (used > largest) largest = used;
            (,,, complete) = battle.jackpotProgress();
        }
        assertTrue(game.rngLocked(), "daily lock survives until post-battle phases");
        emit log_named_uint("native_jackpot_battle_steps", steps);
        emit log_named_uint("native_jackpot_battle_largest_tx_including_intrinsic", largest);
    }

    /// @dev The consolidation stage after the battle: BAF arming, decimator, yield surplus, growth
    ///      round and level quest in one transaction. The BAF awards it reserves are drawn and paid
    ///      in the following award stage.
    function _checkConsolidation(bool measureComposition) private {
        CenturyNativeGasHost host = CenturyNativeGasHost(payable(address(game)));
        (uint8 stage, uint256 used, Vm.Log[] memory logs) = _nativePhaseTx();
        assertEq(host.bafPool(), expectedPool, "the armed BAF pool is the fixture's");
        Tally memory c = _newTally();
        _tally(c, logs);
        emit log_named_uint("century_consolidation_including_intrinsic", used);
        emit log_named_uint("BAF_pool_wei", expectedPool);
        emit log_named_uint("house_high_passes", c.highPasses);
        assertEq(stage, STAGE_ENTERED_JACKPOT, "century consolidation must finish");
        assertEq(c.ethAwards + c.ticketAwards + c.whaleAwards, 0, "arming pays no award");
        assertEq(c.decimator, 1, "nonempty decimator must resolve");
        assertEq(c.yieldEvents, 1, "surplus must distribute");
        assertEq(c.growth, 1, "growth round must seal");
        assertEq(c.quest, 1, "new level quest must roll");
        if (expectHousePass) assertGt(c.highPasses, 0, "house pass credit must execute");
        (uint8 kind, uint16 cursor, uint32 count, uint128 reserved) = host.bafWork();
        assertEq(kind, 7, "the BAF award stage is armed");
        assertEq(cursor, 0, "no award is paid at arming");
        assertEq(count, positions, "R round pairs and three head awards");
        assertEq(
            reserved, BafSchedule.ethTermsR(expectedPool, 0, positions, rounds), "reservation is the schedule's ETH term"
        );
        assertLt(used, GasBounds.POOL_CONSOLIDATION, "native century phase exceeds saved admission bound");
        assertLe(GasBounds.POOL_CONSOLIDATION + GasBounds.DAILY_PHASE_TAIL + MineFlipGas.CHECK_RESERVE, CAP,
            "declared consolidation plus tail exceeds the 10M chunk limit");

        if (measureComposition) _checkRealisticMinerCalls("century_composed_baf_awards_including_intrinsic");
        _checkBafAwardStage(used);
    }

    /// @dev Engine accounts the award stage touches start every measured call cold.
    function _coolEngine() private {
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        vm.cool(address(jackpots));
        vm.cool(address(coinflip));
    }

    /// @dev Drives the award stage at the fixture's composed allowance (several groups per call),
    ///      returning the call count, summed cold gas and award-stream digest.
    function _driveComposedStage() private returns (uint256 calls, uint256 total, bytes32 digest) {
        CenturyNativeGasHost host = CenturyNativeGasHost(payable(address(game)));
        uint8 kind = 7;
        while (kind == 7) {
            assertLt(calls, positions / BAF_GROUP + 2, "the composed BAF award stage stalled");
            _coolEngine();
            vm.recordLogs();
            MineFlipGas.Result memory result = host.dailyWith{gas: 12_000_000}(COMPOSED_ALLOWANCE);
            total += _coldCallGas();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertTrue(result.progressed, "a composed award call makes progress");
            assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "the BAF award stage ran");
            digest = BafSchedule.chain(digest, logs);
            (kind,,,) = host.bafWork();
            ++calls;
        }
    }

    /// @dev Drives the award stage one group per call. Each call starts cold; before it, a reference
    ///      run of the group and the bracket views draw each of its pairs on the state the pair starts
    ///      from (`BafPairDraw`), and the call must pay the schedule's amounts and legs to exactly
    ///      those winners, reduce the reservation by the ETH it credits, and leave the board
    ///      untouched until the last group closes it. Every position is filled, so no residue
    ///      returns: claimablePool and futurePool are unchanged by the stage. A composed run of the
    ///      same stage (several groups per call) must emit the identical award stream.
    function _checkBafAwardStage(uint256 consolidationUsed) private {
        CenturyNativeGasHost host = CenturyNativeGasHost(payable(address(game)));
        (uint256 claimableBefore, uint256 futureBefore, uint256 pendingBefore) = host.poolsProbe();
        uint256 levelBefore = CenturyBafScores.levelWord(address(jackpots));

        uint256 snapshot = vm.snapshotState();
        (uint256 composedCalls, uint256 composedTotal, bytes32 composedDigest) = _driveComposedStage();
        vm.revertToState(snapshot);

        Tally memory a = _newTally();
        StageRun memory run;
        uint256 calls;
        run.groupGas = new uint256[]((positions + BAF_GROUP - 1) / BAF_GROUP);
        for (uint256 cursor; cursor < positions; cursor += BAF_GROUP) {
            assertLt(calls, positions / BAF_GROUP + 1, "the BAF award stage stalled");
            Vm.Log[] memory logs = _runGroup(run, calls, cursor);
            _tally(a, logs);
            if (cursor + BAF_GROUP < positions) {
                assertEq(CenturyBafScores.levelWord(address(jackpots)), levelBefore, "the bracket stays frozen mid-stage");
            }
            ++calls;
        }
        assertEq(calls, (positions + BAF_GROUP - 1) / BAF_GROUP, "one call per group");
        uint256 levelAfter = CenturyBafScores.levelWord(address(jackpots));
        assertEq(uint64(levelAfter), uint64(levelBefore) + 1, "the last group bumps the bracket epoch");
        assertEq(uint8(levelAfter >> 64), 0, "and empties the board");
        for (uint256 i; i < 4; ++i) assertEq(CenturyBafScores.topEntry(address(jackpots), i), 0, "board entry cleared");
        (uint256 claimableAfter, uint256 futureAfter, uint256 pendingAfter) = host.poolsProbe();
        assertEq(claimableAfter, claimableBefore, "award groups pay from the reservation");
        assertEq(futureAfter, futureBefore, "a fully filled schedule returns no residue");
        assertEq(pendingAfter, pendingBefore, "nor to the pending pool");
        assertEq(run.digest, composedDigest, "one group per call pays the composed run's award stream");

        _logStage(run, consolidationUsed, composedCalls, composedTotal);
        emit log_named_uint("BAF_ETH_awards", a.ethAwards);
        emit log_named_uint("BAF_ticket_rolls", a.ticketAwards);
        emit log_named_uint("BAF_whale_awards", a.whaleAwards);
        emit log_named_uint("BAF_distinct_recipients", a.distinct);
        emit log_named_uint("distinct_ticket_recipient_level_pairs", a.distinctTicketPairs);
        emit log_named_uint("far_future_ticket_rolls", a.farRolls);
        if (_rngWord() != WORD) {
            // Destination-heavy variants retain at least the current fixture's pressure: a small
            // margin under the measured spread (98 pairs / 15 far rolls).
            assertGe(a.distinctTicketPairs, 95, "distinct cold destination pressure");
            assertGe(a.farRolls, 13, "far-future destination pressure");
        }
        assertEq(a.ethAwards, rounds + 3, "full distinct BAF ETH set");
        assertEq(a.ticketAwards, expectedRolls, "amount-dependent ticket work");
        assertEq(a.whaleAwards, expectedWhales, "amount-dependent whale deferrals");
        assertEq(a.distinct, positions, "every logical recipient must be awarded");
        assertEq(a.decimator + a.yieldEvents + a.growth + a.quest, 0, "the award stage runs no consolidation step");
        assertLe(GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL + GasBounds.DAILY_PHASE_TAIL
            + MineFlipGas.CHECK_RESERVE, CAP, "declared BAF group plus tails exceeds the 10M chunk limit");
    }

    /// @dev One measured group call starting at `cursor`, checked against the reference draw.
    function _runGroup(StageRun memory run, uint256 g, uint256 cursor) private returns (Vm.Log[] memory logs) {
        CenturyNativeGasHost host = CenturyNativeGasHost(payable(address(game)));
        (uint8 kind, uint16 at,, uint128 reservedBefore) = host.bafWork();
        assertEq(kind, 7, "the award stage is pending");
        assertEq(at, cursor, "exactly one fixed group per admitted allowance");
        uint256 end = cursor + BAF_GROUP < positions ? cursor + BAF_GROUP : positions;
        (uint32[] memory atStart, uint32[] memory expected, bytes32 refDigest) = _referenceDraw(cursor, end);

        _coolEngine();
        vm.recordLogs();
        MineFlipGas.Result memory result = host.dailyWith{gas: 12_000_000}(ONE_GROUP_ALLOWANCE);
        uint256 used = _coldCallGas();
        logs = vm.getRecordedLogs();
        assertTrue(result.progressed, "one award group is admitted");
        assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "the BAF award stage ran");
        assertEq(BafSchedule.chain(bytes32(0), logs), refDigest, "the measured call repeats the reference run");
        uint256 credited = _checkGroupAwards(run, logs, cursor, end, atStart, expected);
        run.digest = BafSchedule.chain(run.digest, logs);

        uint128 reservedAfter;
        (kind, at,, reservedAfter) = host.bafWork();
        if (end < positions) {
            assertFalse(result.done, "the stage continues");
            assertEq(kind, 7, "the work record stays armed");
            assertEq(at, end, "the cursor advances by one group");
            assertEq(reservedBefore - reservedAfter, credited, "the reservation tracks the credited ETH");
            if (used > run.worst) {
                run.worst = used;
                run.worstGroup = g;
            }
        } else {
            assertTrue(result.done, "the last group completes the stage");
            assertEq(kind, 0, "the last group deletes the work record");
            assertEq(reservedBefore, credited, "every position filled: no residue");
        }
        assertLe(used, GasBounds.BAF_AWARD_GROUP, "a BAF award group exceeds its saved bound");
        run.groupGas[g] = used;
        run.groupSum += used;
        emit log_named_string(
            string.concat("baf_group_", vm.toString(g)),
            string.concat(vm.toString(used), " gas, ", _composition(logs))
        );
    }

    /// @dev A run of the group from its start, then the reference draw (`BafPairDraw`) from its
    ///      award events; the state is back at the group's start afterwards. Returns the award-stream
    ///      digest of that run.
    function _referenceDraw(uint256 cursor, uint256 end)
        private
        returns (uint32[] memory atStart, uint32[] memory expected, bytes32 refDigest)
    {
        uint256 pre = vm.snapshotState();
        vm.recordLogs();
        CenturyNativeGasHost(payable(address(game))).dailyWith{gas: 12_000_000}(ONE_GROUP_ALLOWANCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.revertToState(pre);
        refDigest = BafSchedule.chain(bytes32(0), logs);
        (BafSchedule.Award[] memory got,) = BafSchedule.awardsOf(logs);
        (atStart, expected) = BafPairDraw.draw(
            address(jackpots), address(game), pre, got, expectedPool, _rngWord(), cursor, end, rounds
        );
        vm.getRecordedLogs();
        vm.deleteStateSnapshot(pre);
    }

    /// @dev The group's award events against the schedule and the reference draw (see
    ///      `BafSchedule.checkGroup`): every position pays the views' draw on the state its pair
    ///      starts from. A group's second pair can differ from the group-start draw only on a
    ///      far-future band, where the first pair's rolls can append a lane at a level the pair
    ///      samples (`moved`); a far-future round's winner can differ from the pre-consolidation draw
    ///      once any earlier roll did so (`redrawn`). Minted-level rounds and head awards read state
    ///      no award changes.
    function _checkGroupAwards(
        StageRun memory run,
        Vm.Log[] memory logs,
        uint256 cursor,
        uint256 end,
        uint32[] memory atStart,
        uint32[] memory expected
    ) private returns (uint256 credited) {
        (BafSchedule.Award[] memory got, bool tagged) = BafSchedule.awardsOf(logs);
        assertTrue(tagged, "BAF award events carry level 100 and the BAF sentinel");
        uint32[] memory paid = new uint32[](end - cursor);
        credited = BafSchedule.checkGroupR(got, expectedPool, cursor, end, expected, paid, rounds);
        for (uint256 i = cursor; i < end; ++i) {
            if (expected[i - cursor] != atStart[i - cursor]) {
                assertTrue(
                    i & 7 >= 4 && i >= rounds && i < 2 * rounds,
                    "only a far-future group's second pair moves with its own rolls"
                );
                ++run.moved;
            }
            if (paid[i - cursor] == predicted[i]) continue;
            assertTrue(i >= rounds && i < 2 * rounds, "only far-future rounds can move with the stage's own rolls");
            ++run.redrawn;
        }
    }

    /// @dev "e ETH, r rolls (f far-future), w whale" for a group's award logs.
    function _composition(Vm.Log[] memory logs) private pure returns (string memory) {
        uint256 eth;
        uint256 rolls;
        uint256 far;
        uint256 whales;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == ETH_SIG) ++eth;
            else if (t0 == WHALE_SIG) ++whales;
            else if (t0 == TICKET_SIG) {
                ++rolls;
                if (uint256(logs[i].topics[2]) >= 102) ++far;
            }
        }
        return string.concat(
            vm.toString(eth), " ETH, ", vm.toString(rolls), " rolls (", vm.toString(far), " far-future), ",
            vm.toString(whales), " whale"
        );
    }

    function _logStage(StageRun memory run, uint256 consolidationUsed, uint256 composedCalls, uint256 composedTotal)
        private
    {
        emit log_named_uint("baf_worst_full_group_cold_including_intrinsic", run.worst);
        emit log_named_uint("baf_worst_full_group_index", run.worstGroup);
        emit log_named_uint("baf_last_group_cold_including_intrinsic", run.groupGas[run.groupGas.length - 1]);
        emit log_named_uint("baf_groups_cold_sum", run.groupSum);
        emit log_named_uint("baf_full_payout_cold_groups_plus_consolidation", consolidationUsed + run.groupSum);
        emit log_named_uint("baf_stage_composed_calls", composedCalls);
        emit log_named_uint("baf_stage_composed_total", composedTotal);
        emit log_named_uint("baf_full_payout_composed_plus_consolidation", consolidationUsed + composedTotal);
        emit log_named_uint("baf_positions_redrawn_after_stage_rolls", run.redrawn);
        emit log_named_uint("baf_positions_moved_by_own_group_rolls", run.moved);
    }

    function _newTally() private view returns (Tally memory t) {
        t.ticketPairs = new bytes32[](2 * positions + 8);
        t.recipients = new uint32[](positions + 8);
    }

    function _lastStage(Vm.Log[] memory logs) private pure returns (uint8 stage) {
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    function _tally(Tally memory t, Vm.Log[] memory logs) private {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_SIG) ++t.ethAwards;
            if (topic == TICKET_SIG) {
                ++t.ticketAwards;
                if (uint256(logs[i].topics[2]) >= 106) ++t.farRolls;
                bytes32 pair = keccak256(abi.encode(logs[i].topics[1], logs[i].topics[2]));
                bool repeatedPair;
                for (uint256 j; j < t.distinctTicketPairs; ++j) {
                    if (t.ticketPairs[j] == pair) repeatedPair = true;
                }
                if (!repeatedPair) t.ticketPairs[t.distinctTicketPairs++] = pair;
                (uint32 entries,,,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
                assertGt(entries, 0, "every ticket roll must perform real queued work");
            }
            if (topic == WHALE_SIG) ++t.whaleAwards;
            if (topic == ETH_SIG || topic == TICKET_SIG || topic == WHALE_SIG) {
                uint32 who = uint32(uint256(logs[i].topics[1]));
                bool found;
                for (uint256 j; j < t.distinct; ++j) {
                    if (t.recipients[j] == who) found = true;
                }
                if (!found) t.recipients[t.distinct++] = who;
            }
            if (topic == keccak256("PoolSkimApplied(uint24,uint256,uint256)")) {
                (uint256 take,) = abi.decode(logs[i].data, (uint256, uint256));
                emit log_named_uint("next_to_future_skim_take", take);
            }
            if (topic == keccak256("DecimatorResolved(uint24,uint256,uint256,uint64)")) {
                ++t.decimator;
                (, uint256 pool, uint64 count) = abi.decode(logs[i].data, (uint256, uint256, uint64));
                emit log_named_uint("decimator_pool_wei", pool);
                // All dimensions draw from the same pre-BAF future snapshot.
                assertLe(
                    pool > expectedPool * 3 / 2 ? pool - expectedPool * 3 / 2 : expectedPool * 3 / 2 - pool,
                    1,
                    "actual pool must match threshold fixture"
                );
                assertEq(count, 1_000_000, "the original entrant count is sealed without a field scan");
            }
            if (topic == keccak256("YieldSurplusDistributed(uint256)")) {
                ++t.yieldEvents;
                assertEq(abi.decode(logs[i].data, (uint256)), 23 ether, "100 ETH real surplus");
            }
            if (topic == keccak256("GrowthRoundSealed(uint24,bool)")) ++t.growth;
            if (topic == keccak256("LevelQuestRolled(uint24,uint8,uint8,uint256)")) ++t.quest;
            if (
                topic == keccak256("CrapsPassesCredited(uint32,bool,uint256)")
                    && uint32(uint256(logs[i].topics[1])) == 2
            ) {
                (bool high, uint256 n) = abi.decode(logs[i].data, (bool, uint256));
                if (high) t.highPasses += n;
            }
        }
    }
}

contract AdvanceCenturyConsolidationGas is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(3500 ether, 100 ether, 158_126_247_524_580_441_470, 100, 1, true);
    }
}

contract AdvanceCenturyAtHundredThreshold is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 475_485_053_530_434_780_923, 100 ether, 102, 0, false);
    }
}

contract AdvanceCenturyAboveHundredThreshold is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 475_485_053_530_434_781_933, 100 ether + 200, 100, 1, false);
    }
}

contract AdvanceCenturyFarDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 880_838_588_883_970_134_458, 180 ether, 100, 1, false);
    }
}

contract AdvanceCenturyLargeDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 1_486_899_194_944_576_195_064, 300 ether, 96, 3, false);
    }
}

/// @dev 490 ETH, 48 rounds: the best's 5.10 ETH ticket leg defers to whale passes, the second's
///      3.06 ETH leg rolls twice.
contract AdvanceCenturyFirstScatterDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 2_446_495_154_540_535_791_024, 490 ether, 48, 27, false);
    }
}

/// @dev 1,800 ETH, 96 rounds (195 positions): both scatter ticket legs (9.375 / 5.625 ETH) and every
///      head lootbox half defer to whale passes.
contract AdvanceCenturyAllTicketsDeferred is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 9_062_656_770_702_151_952_640, 1800 ether, 0, 99, false);
    }
}

/// @dev 600 ETH, 96 rounds (195 positions): every scatter ticket leg (3.125 / 1.875 ETH) rolls twice,
///      the doubled schedule's most roll-heavy shape.
contract AdvanceCenturyDoubledRounds is CenturyConsolidationFixture {
    function _shape() internal pure override returns (Shape memory) {
        return Shape(100 ether, 3_002_050_710_096_091_346_579, 600 ether, 192, 3, false);
    }
}

/// @dev Word 158931: its ticket legs reach 98 distinct recipient/level pairs and 15 far-future
///      rolls, the widest spread at 98 pairs among the odd words below 200,001.
contract AdvanceCenturyDiverseDestinations is CenturyConsolidationFixture {
    function _rngWord() internal pure override returns (uint256) {
        return 158_931;
    }

    function _shape() internal pure override returns (Shape memory) {
        // Future funding sized for the 15% trough; this word's skim rolls put the BAF pool at
        // 178.04 ETH, inside the (100, 200) ETH band with the destination-heavy award shape:
        // 2-roll scatter legs and head halves, the top award's half deferred to whale passes.
        // This pool's level cut falls short of one whole high pass: no house pass.
        return Shape(3000 ether, 38_181_818_181_818_181_818, 178_035_451_782_491_666_369, 100, 1, false);
    }
}

contract AdvanceCenturyVaultHistorySuccessful is AdvanceCenturyDiverseDestinations {
    function _vaultHistoryMode() internal pure override returns (uint8) {
        return 1;
    }
}

contract AdvanceCenturyVaultHistoryFailed is AdvanceCenturyDiverseDestinations {
    function _vaultHistoryMode() internal pure override returns (uint8) {
        return 2;
    }
}
