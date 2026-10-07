// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ProtocolBoonDrawSeeder} from "./helpers/ProtocolBoonDrawSeeder.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {AdvanceStageStream} from "../helpers/AdvanceStageStream.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {CrapsSlots} from "../helpers/GameSlots.sol";

/// @title PurchaseDailyWorstCase — the purchase-phase daily stages at their winner caps.
/// @notice Stage 6 pays 105 ETH winners (or level one's 50 trait shares) and prices tickets.
///         Stage 15 pays up to 192 tickets and seals the day; without tickets, stage 6 seals it.
///         A fresh daily request also locks the day's jackpot battle: once the VRF word lands it
///         applies (stage 18), the battle runs its stage-17 steps, and only then do stages 6 and
///         15 run. The held RNG lock freezes inputs between transactions. Seeded days record their
///         word without a request, so they lock no battle; the word-apply variants drive the real
///         request, VRF callback and battle.
/// @dev All stages use the real protocol. The engine composes every admitted checkpoint into a
///      call, so stages are read from the ordered log stream (AdvanceStageStream), each call at the
///      smallest admitting rung of a realistic allowance ladder. No whole-call gas ceiling is
///      asserted (owner rule: one admitted chunk is the unit; jackpot groups are bounded by
///      JackpotTicketAwardChunks / JackpotCheckpoints); the largest call per stage is logged.
contract PurchaseDailySeeder is DegenerusGame, BucketSeed {
    struct Shape {
        uint24 lvl; // storage `level`; the daily pays purchaseLevel = lvl + 1
        uint256 word; // the day's recorded VRF word
        uint160 base; // disjoint address-space base for synthetic holders
        uint256 mainHolders; // distinct holders per main-board bucket at purchaseLevel (ETH + ticket legs)
        uint256 bonusHolders; // distinct holders per DECOY bucket at purchaseLevel+1..+4, keyed on a
            // second, unrelated trait roll unused by any real draw; kept populated to prove the
            // purchase coin draws ignore minted-ahead boards
        uint256 ffHolders; // distinct holders per far-future queue at purchaseLevel+1..+99 (the
            // jackpot battle's award draw)
        uint128 nextPool; // nextPrizePool (> prevPool latches last-purchase; + BAF arm at x0)
        uint128 futurePool; // futurePrizePool: the drip sizes the ETH and ticket legs
        uint256 prevPool; // levelPrizePool[purchaseLevel-1]: the latch target and a fresh request's Added
        uint256 traitHolders; // distinct holders per board bucket at purchaseLevel (level-1 trait draw)
    }

    function seedPurchaseDaily(Shape calldata s, uint8[4] calldata mainTraits, uint8[4] calldata decoyTraits)
        external
    {
        uint24 day = _simulatedDayIndex();
        uint24 pl = s.lvl + 1;
        // The synthetic jump models every level below this one as drained: free their recycled
        // queue roots so the day's awards and seeded queues can bind.
        TQ.retireCompleted(address(this), s.lvl);

        // Purchase-phase day shape: day == dailyIdx + 1, the day's request locked with its word
        // already recorded (rngGate returns it; no request, no subscriber stage), read slot
        // drained, no coin-ticket leg pending, no golden ticket, no hero wagers.
        level = s.lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        jackpotFlags = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        jackpotCounter = 0;
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = s.word < 2 ? RNG_WORD_WAITING : s.word;
        _recordDailyRng(day, s.word);
        vrfRequestId = 1;
        // The daily phase of a delivered, published request: the engine selects DailyPhase only
        // for an active, published, not-yet-complete session.
        rngRequestDay = day;
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
        levelPrizePool[s.lvl] = s.prevPool;
        currentPrizePool = uint128(100 ether);
        _setPrizePools(s.nextPool, s.futurePool);

        // The empty-board split excludes protocol participation too: genesis deity passes supply
        // virtual bucket entries. A level-1 trait draw excludes them as well — a deity lands on
        // VAULT / sDGNRS, whose seat is refused (cheaper than a fresh seat).
        if (s.bonusHolders == 0 || s.traitHolders != 0) {
            deityBySymbol[VAULT_DEITY_SYMBOL] = 0;
            deityBySymbol[SDGNRS_DEITY_SYMBOL] = 0;
        }
        // Level 1: genesis tickets sit in level 1's queues and would be drained (their own stage)
        // ahead of the draws once a fresh word swaps the slots. Empty both slots so the word-apply
        // variant reaches the trait draw as soon as its battle completes.
        if (s.traitHolders != 0) {
            uint256[] storage q0 = ticketQueue[_ticketQueueStorageKey(pl)];
            uint256[] storage q1 = ticketQueue[_ticketQueueStorageKey(pl | TICKET_SLOT_BIT)];
            assembly ("memory-safe") {
                sstore(q0.slot, 0)
                sstore(q1.slot, 0)
            }
        }
        // Empty every unminted queue the battle's award draw reads, then seed only fresh distinct wallets.
        for (uint24 c = pl + 1; c <= pl + 99; ++c) {
            uint256[] storage emptyQueue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(c))];
            assembly ("memory-safe") { sstore(emptyQueue.slot, 0) }
        }

        // Keep registry position 0 out of every seeded level (a zero lane index understates gas).
        for (uint24 L = pl; L <= pl + 4; ++L) {
        }

        for (uint8 q; q < 4; ++q) {
            if (s.mainHolders != 0) {
                _seedBucketDistinct(pl, mainTraits[q], s.mainHolders, s.base + uint160(q) * 0x100000);
            }
            if (s.traitHolders != 0) {
                _seedBucketDistinct(pl, mainTraits[q], s.traitHolders, s.base + 0x4000000 + uint160(q) * 0x100000);
            }
            if (s.bonusHolders != 0) {
                // Only current/next minted buckets coexist; farther queues stay ungenerated.
                for (uint24 k; k < 1; ++k) {
                    _seedBucketDistinct(
                        pl + 1 + k,
                        decoyTraits[q],
                        s.bonusHolders,
                        s.base + 0x800000 + uint160(k) * 0x400000 + uint160(q) * 0x100000
                    );
                }
            }
        }

        if (s.ffHolders != 0) {
            for (uint24 c = pl + 1; c <= pl + 99; ++c) {
                uint160 b = s.base + 0x2000000 + uint160(c - pl - 1) * 0x1000;
                for (uint256 i; i < s.ffHolders; ++i) {
                    _tqAppend(_tqFarFutureKey(c), _seedWallet(address(b + uint160(i + 1))));
                }
            }
        }
    }

    /// @dev Un-record the day's word: the day is fresh and unlocked, so the next advance fires the
    ///      real VRF request, which also locks the day's jackpot battle.
    function unrecordWord() external {
        uint24 day = _simulatedDayIndex();
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = RNG_WORD_WAITING;
        _recordDailyRng(day, 0);
        vrfRequestId = 1;
        rngRequestTime = 1;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        humanReadComplete = true;
        prizePoolFrozen = false;
    }
}

/// @dev The word-apply leg, driven for real: book the craps table's 7-day action window (so
///      openBonusDay draws a high budget and posts stakes), settle Coinflip through day-1 (so the
///      measured sDGNRS settle walks exactly one day, the steady-state shape, not the day-400 jump),
///      fire the day's VRF request from the real mineFlip (which locks the day's jackpot battle),
///      and fulfil it on the mock coordinator. The word then applies as its own indivisible action
///      (stage 18: _applyDailyRng, coinflip.processCoinflipPayouts, quests.rollDailyQuest, craps
///      openBonusDay, _finalizeLootboxRng); the battle's steps follow, then the day's own stages.
abstract contract FreshWordLeg is AdvanceStageStream {
    uint8 internal constant STAGE_RNG_REQUESTED_ = 1;
    uint8 internal constant STAGE_RNG_APPLIED_ = 18;
    uint256 internal constant CRAPS_DAY_STAKED_SLOT = CrapsSlots.DAY_STAKED; // CrapsBattle `_dayStaked`
    /// @dev Historical per-transaction battle figure. Not asserted here: one 50-entry field group is
    ///      bounded per chunk by JackpotMergeAdvance (declared JACKPOT_BATTLE_DRAW envelope).
    uint256 internal constant BATTLE_TX_LIMIT = 10_000_000;

    function _armFreshWord(uint256 word, uint24 day) internal {
        // Booked table: 1M FLIP of action per day over the window, half of it high action.
        for (uint24 i = 1; i <= 7; ++i) {
            bytes32 slot = keccak256(abi.encode(uint256(day - i), CRAPS_DAY_STAKED_SLOT));
            vm.store(address(crapsBattle), slot, bytes32((uint256(500_000 ether) << 128) | uint256(1_000_000 ether)));
        }
        // Yesterday resolved: flipsClaimableDay = day-1, sDGNRS settled to it.
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, uint256(keccak256("yesterday")) | 1, day - 1);

        // The synthetic day-400 jump leaves expired Craps maintenance (one checkpoint per call)
        // ahead of the request; the call that sends it ends on the request marker.
        uint256 before = mockVRF.lastRequestId();
        uint8 st = 255;
        for (uint256 calls; calls < 1000 && mockVRF.lastRequestId() == before; ++calls) {
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) (st,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        require(st == STAGE_RNG_REQUESTED_, "arm: the request stage ran");
        uint256 reqId = mockVRF.lastRequestId();
        require(reqId == before + 1, "arm: one VRF request fired");
        mockVRF.fulfillRandomWords(reqId, word);
        // Include both funded deity pools at the maximum uint32 search depth in
        // every measured fresh-word composition, not just a standalone draw.
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ProtocolBoonDrawSeeder).runtimeCode);
        ProtocolBoonDrawSeeder(address(game)).seedPools(day, word);
        vm.etch(address(game), original);
        streamCursor = streamLogs.length;
    }

    /// @dev Logs emitted by the coinflip and craps contracts: the word-apply leg's own footprint.
    function _countLegLogs(Vm.Log[] memory logs) internal view returns (uint256 coinflipLogs, uint256 crapsLogs) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip)) ++coinflipLogs;
            else if (logs[i].emitter == address(crapsBattle)) ++crapsLogs;
        }
    }

    /// @dev Logs in `logs` whose first topic is `sig`.
    function _countTopic(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) ++n;
        }
    }

    /// @dev ETH and ticket winner logs: the daily legs a word-apply or battle tx never carries.
    function _dailyLegLogs(Vm.Log[] memory logs) internal pure returns (uint256) {
        return _countTopic(logs, keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)"))
            + _countTopic(logs, keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)"));
    }

    /// @dev One mineFlip call at a realistic 10M allowance: its last stage marker, its gas
    ///      (intrinsic included) and its logs.
    function _advanceTx(bool) internal returns (uint8 stage, uint256 used, Vm.Log[] memory logs) {
        vm.recordLogs();
        game.mineFlip{gas: 10_000_000}();
        // With isolation, Foundry includes calldata intrinsic in the top-level CALL cost.
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
        logs = vm.getRecordedLogs();
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    /// @dev The logs [from, to] of the stream as a memory array.
    function _streamSlice(uint256 from, uint256 to) internal view returns (Vm.Log[] memory logs) {
        logs = new Vm.Log[](to + 1 - from);
        for (uint256 i = from; i <= to; ++i) logs[i - from] = streamLogs[i];
    }

    /// @dev The fresh word's application: the next stage run must be stage 18 alone, carrying the
    ///      coinflip settlement and the craps day it opens, no daily leg and no battle entry.
    ///      Returns the largest call's gas (intrinsic included) and the run's logs.
    function _applyWord(bool, uint256) internal returns (uint256 used, Vm.Log[] memory logs) {
        (uint256 from, uint256 to, uint256 maxGas) = _runThroughMarker(STAGE_RNG_APPLIED_, 50);
        uint8 stage = _markerStage(to);
        used = maxGas;
        logs = _streamSlice(from, to);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(logs);
        emit log_named_uint("word_apply_tx_incl_intrinsic", used);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        assertEq(stage, STAGE_RNG_APPLIED_, "the fresh word applies");
        // Its call carries no later stage: the smallest admitting allowance for the indivisible
        // application leaves less than the next battle group's admission.
        assertFalse(_markerAfter(to), "the fresh word applies alone");
        for (uint256 i = from; i < to; ++i) assertFalse(_isMarker(i), "no stage precedes the application");
        assertEq(_dailyLegLogs(logs), 0, "the word-apply tx pays no daily leg");
        assertEq(
            _countTopic(logs, keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)")),
            0,
            "the word-apply tx draws no battle entry"
        );
        assertGe(cfLogs, 1, "coinflip.processCoinflipPayouts ran in the word-apply tx");
        assertGe(crLogs, 8, "craps openBonusDay opened the day's windows in the word-apply tx");
    }

    /// @dev Steps the day's locked jackpot battle to completion: one stage run of `battleStage`
    ///      markers, paying no ETH or ticket winner, closed by the day's own next stage.
    function _driveBattle(uint8 battleStage) internal returns (uint256 steps) {
        IJackpotBattle battle = IJackpotBattle(address(crapsBattle));
        (uint8 stage, uint256 from, uint256 to, uint256 largest) = _nextStageRun(200);
        assertEq(stage, battleStage, "a battle step runs from its own stage");
        assertEq(_dailyLegLogs(_streamSlice(from, to)), 0, "a battle step shares no daily leg");
        (,,, bool complete) = battle.jackpotProgress();
        assertTrue(complete, "the battle completed");
        steps = streamLogCall[to] + 1 - streamLogCall[from];
        // The battle closed on the day's next marker, under the same daily lock.
        assertLt(streamCursor, streamLogs.length, "the day's own stages follow the battle");
        emit log_named_uint("jackpot_battle_steps", steps);
        emit log_named_uint("jackpot_battle_largest_tx_incl_intrinsic", largest);
    }
}

/// @dev Shared measurement seam: warp, etch-seed-restore, drive the live mineFlip, classify winners.
abstract contract PurchaseDailyFixture is AdvanceStageStream {
    /// @dev EIP-7825 per-transaction gas cap. A single mineFlip tx above this is a permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev The 10M soft design target the drains are sized to (USER dual bound).
    uint256 internal constant GAS_TARGET = 10_000_000;
    /// @dev Intrinsic cost of a zero-arg mineFlip() tx: 21,000 base + 4 non-zero calldata bytes.
    uint256 internal constant INTRINSIC = 21_064;

    bytes32 internal constant ETH_WIN_SIG = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(uint32,uint24,uint8,uint256,uint256)");
    bytes32 internal constant BATTLE_ENTRY_SIG = keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)");
    bytes32 internal constant BAF_ARMED_SIG = keccak256("BafDrawArmed(uint24)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint8 internal constant STAGE_PURCHASE_BATTLE = 17;
    // ETH winner targets [32,16,4] double from 40 ETH (5b25fded0): the ~46 ETH leg pays
    // 64 + 32 + 8 + the solo (each 20% share funds more than its target in 0.1 ETH units).
    uint16 internal constant PURCHASE_ETH_WINNERS = 105;
    // Ticket winner cap 96, doubled at 40 ETH of value (5b25fded0): the ~75 ETH leg pays 192.
    uint16 internal constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 192;
    uint256 internal constant COIN_DRAW_SHARES = 50; // level-1 trait draw's FLIP-only share cap

    /// @dev level 109 -> purchaseLevel 110: an x0 (BAF) purchase level at the 0.04 ETH price, so the
    ///      target-met latch also arms the BAF draw.
    uint24 internal constant LVL = 109;
    uint160 internal constant BASE = uint160(0x1000000000);
    uint256 internal constant MAIN_HOLDERS = 5000; // per main bucket: ~60 draws each, ~0.4 expected repeats
    uint256 internal constant BONUS_HOLDERS = 200; // minted-ahead boards the purchase draws must ignore
    uint256 internal constant FF_HOLDERS = 8; // per unminted level: the award draw's field on a fresh request
    uint256 internal constant L1_TRAIT_HOLDERS = 5000; // per level-1 board bucket: ~12 pulls each

    /// @dev Sizing at 0.04 ETH. The future pool's drip sizes the ETH and ticket legs. The recorded
    ///      previous pool is the last-purchase target and, on a fresh request, the jackpot battle's
    ///      Added: 0.5% of it at the level price (125 FLIP per ETH here), at least 50,000 FLIP, one
    ///      award per 10,000.
    ///      - FUTURE_POOL 5000 ETH -> the drip covers 105 ETH winners and 192 whole-ticket winners.
    ///      - PREV_POOL_OPEN25 2,080 ETH -> 260,000 FLIP of Added: a 26-award battle.
    ///      - PREV_POOL_FLOOR 340 ETH -> 42,500 FLIP, raised to the floor: a 5-award battle.
    ///      next = prev + 1 ETH > target -> the last-purchase latch (+ BAF arm at x0).
    uint128 internal constant FUTURE_POOL = 5000 ether;
    uint256 internal constant PREV_POOL_OPEN25 = 2080 ether;
    uint256 internal constant PREV_POOL_FLOOR = 340 ether;
    uint128 internal constant NEXT_POOL_LATCH = 1001 ether;
    uint128 internal constant NEXT_POOL_QUIET = 50 ether;
    /// @dev Level 1 (storage level 0, 0.01 ETH): the trait draw's budget is B = prev * 250 FLIP and its
    ///      FLIP-only share cap (units = B / 100 FLIP, capped at COIN_DRAW_SHARES = 50) saturates at
    ///      B >= 5,000 FLIP. PREV_POOL_L1_MAX 5,000 ETH also gives a fresh request 2,500,000 FLIP of
    ///      Added: a 250-award battle.
    uint256 internal constant PREV_POOL_L1_MAX = 5000 ether;

    struct Tally {
        uint8 stage;
        uint256 ethWins;
        uint256 ethDistinct;
        uint256 ticketWins;
        uint256 ticketDistinct;
        uint256 flipWins; // trait-draw coin shares (JackpotFlipWin)
        uint256 battleEntries; // awarded jackpot battle entries (JackpotBattleEntry)
        uint256 coinDistinct; // distinct trait-draw recipients
        bool bafArmed;
    }

    function _word(bytes32 tag) internal pure returns (uint256) {
        uint256 word = uint256(keccak256(abi.encodePacked(tag))) | 1;
        while (true) {
            uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
            bool gold;
            for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) gold = true;
            if (!gold) return word;
            word += 2;
        }
    }

    /// @dev Day 400 puts every seeded slot far past the deploy program — the cold, worst-case shape.
    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    function _seed(PurchaseDailySeeder.Shape memory s) internal {
        _deployProtocol();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(s.word);
        // A second, unrelated trait roll used only to seed decoy buckets at minted-ahead levels
        // (see Shape.bonusHolders) — no real draw reads it.
        uint8[4] memory decoyT =
            JackpotBucketLib.getRandomTraits(EntropyLib.hash2(s.word, uint256(keccak256("decoy-ahead-board"))));

        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(PurchaseDailySeeder).runtimeCode);
        PurchaseDailySeeder(payable(address(game))).seedPurchaseDaily(s, mainT, decoyT);
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
    }

    function _seedFresh(PurchaseDailySeeder.Shape memory s) internal {
        _seed(s);
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(PurchaseDailySeeder).runtimeCode);
        PurchaseDailySeeder(payable(address(game))).unrecordWord();
        vm.etch(address(game), realCode);
    }

    Vm.Log[] internal lastLogs;

    function _shape(uint256 mainHolders, uint256 bonusHolders, uint256 ffHolders, uint128 nextPool, uint256 prevPool)
        internal
        pure
        returns (PurchaseDailySeeder.Shape memory s)
    {
        s.lvl = LVL;
        // This word pays 105 distinct ETH and 192 distinct ticket recipients at the full caps
        // (re-searched for the 5b25fded0 caps; the old tag's word drew 8 repeat ticket winners).
        s.word = _word(keccak256(abi.encode("purchase-daily-eight-groups", uint256(0))));
        s.base = BASE;
        s.mainHolders = mainHolders;
        s.bonusHolders = bonusHolders;
        s.ffHolders = ffHolders;
        s.nextPool = nextPool;
        s.futurePool = FUTURE_POOL;
        s.prevPool = prevPool;
    }

    /// @dev The level-1 day: storage level 0, no main board (no ETH leg at level 1), the trait
    ///      draw's four buckets at level 1 and the battle's award queues at 2..100.
    function _shapeLevelOne(uint256 prevPool, bool latch) internal pure returns (PurchaseDailySeeder.Shape memory s) {
        s = _shape(0, 0, FF_HOLDERS, latch ? uint128(prevPool + 1 ether) : NEXT_POOL_QUIET, prevPool);
        s.lvl = 0;
        s.traitHolders = L1_TRAIT_HOLDERS;
    }

    /// @dev The next daily stage run from the ordered log stream (see AdvanceStageStream): its
    ///      stage, a tally of the logs it produced, and the largest call that carried them
    ///      (intrinsic included). Each call took the smallest admitting realistic allowance.
    function _measure() internal returns (uint256 used, Tally memory t) {
        (uint8 stage, uint256 from, uint256 to, uint256 maxGas) = _nextStageRun(200);
        used = maxGas;
        t.stage = stage;
        delete lastLogs;
        for (uint256 i = from; i <= to; ++i) lastLogs.push(streamLogs[i]);
        address[] memory ethW = new address[](PURCHASE_ETH_WINNERS + 8);
        address[] memory tkW = new address[](PURCHASE_PHASE_TICKET_MAX_WINNERS + 8);
        address[] memory coinW = new address[](COIN_DRAW_SHARES + 8);
        for (uint256 i; i < lastLogs.length; ++i) {
            if (lastLogs[i].topics.length == 0) continue;
            bytes32 t0 = lastLogs[i].topics[0];
            if (t0 == ETH_WIN_SIG) {
                address w = address(uint160(uint256(lastLogs[i].topics[1])));
                if (_pushDistinct(ethW, t.ethWins, w)) ++t.ethDistinct;
                ++t.ethWins;
            } else if (t0 == TICKET_WIN_SIG) {
                address w = address(uint160(uint256(lastLogs[i].topics[1])));
                if (_pushDistinct(tkW, t.ticketWins, w)) ++t.ticketDistinct;
                ++t.ticketWins;
            } else if (t0 == FLIP_WIN_SIG) {
                address w = address(uint160(uint256(lastLogs[i].topics[1])));
                if (_pushDistinct(coinW, t.flipWins, w)) ++t.coinDistinct;
                ++t.flipWins;
            } else if (t0 == BATTLE_ENTRY_SIG) {
                ++t.battleEntries;
            } else if (t0 == BAF_ARMED_SIG) {
                t.bafArmed = true;
            }
        }
        emit log_named_uint("largest_call_gas_incl_intrinsic", used);
        emit log_named_uint("distance_to_10M_target", used < GAS_TARGET ? GAS_TARGET - used : 0);
    }

    /// @dev With isolation, Foundry includes calldata intrinsic in the top-level CALL cost.
    ///      Otherwise add it once. Read the call cost before any further contract calls.
    function _transactionGas() internal view returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += INTRINSIC;
    }

    /// @dev Appends `w` at `n` and reports whether it was unseen among the first `n` (O(n^2), n <= 192).
    function _pushDistinct(address[] memory arr, uint256 n, address w) private pure returns (bool fresh) {
        fresh = true;
        for (uint256 j; j < n && j < arr.length; ++j) {
            if (arr[j] == w) {
                fresh = false;
                break;
            }
        }
        if (n < arr.length) arr[n] = w;
    }

    function _emitTally(string memory label, uint256 used, Tally memory t) internal {
        emit log_string(label);
        emit log_named_uint("  advance_gas", used);
        emit log_named_uint("  stage", t.stage);
        emit log_named_uint("  eth_wins", t.ethWins);
        emit log_named_uint("  eth_distinct_winners", t.ethDistinct);
        emit log_named_uint("  ticket_wins", t.ticketWins);
        emit log_named_uint("  ticket_distinct_winners", t.ticketDistinct);
        emit log_named_uint("  trait_coin_shares", t.flipWins);
        emit log_named_uint("  jackpot_battle_entries", t.battleEntries);
        emit log_named_uint("  coin_draw_distinct_recipients", t.coinDistinct);
        emit log_named_uint("  baf_armed", t.bafArmed ? 1 : 0);
    }

    /// @dev The priced ticket leg: the next stage, same word, 192 distinct cold winners, sealing the day.
    function _measureTicketStage(string memory label, bool expectBaf) internal returns (uint256 used) {
        Tally memory tk;
        (used, tk) = _measure();
        _emitTally(label, used, tk);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 192-winner cap");
        assertEq(tk.ticketDistinct, PURCHASE_PHASE_TICKET_MAX_WINNERS, "all ticket winners are distinct cold addresses");
        assertEq(tk.ethWins + tk.flipWins + tk.battleEntries, 0, "only the ticket leg rides the ticket stage");
        assertEq(tk.bafArmed, expectBaf, "the sealing stage latches (and arms the BAF draw) iff the target is met");
    }
}

/// @notice The purchase sequence: 105 ETH plus ticket pricing, then 192 tickets and the target-met
///         latch/BAF arm. Each transaction is measured alone. The seeded day locks no battle.
abstract contract PurchaseDailyStage is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public virtual {
        _seed(_shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, uint128(_prev() + 1 ether), _prev()));
    }

    function test_PurchaseDaily_49Eth_TicketPricing_Measured() public virtual {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("PURCHASE_DAILY (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("PURCHASE_DAILY_STAGE_GAS_", _label()), used);
        _assertStage(t);
        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 192 tickets + latch + BAF arm", true);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TICKET_STAGE_GAS_", _label()), ticketUsed);
    }

    /// @dev A purchase day rolls and emits exactly one board.
    function _assertNoPurchaseBonusSet() internal view {
        bytes32 sig = keccak256("DailyWinningTraits(uint24,uint32)");
        uint256 seen;
        for (uint256 i; i < lastLogs.length; ++i) {
            if (lastLogs[i].topics.length == 0 || lastLogs[i].topics[0] != sig) continue;
            uint32 mainSet = abi.decode(lastLogs[i].data, (uint32));
            assertTrue(mainSet != 0, "the purchase day rolled no board");
            ++seen;
        }
        assertEq(seen, 1, "the purchase day did not emit its winning traits once");
    }

    function _assertStage(Tally memory t) internal {
        _assertNoPurchaseBonusSet();
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "the ETH leg paid all 105 scaled-target winners");
        assertEq(t.ethDistinct, PURCHASE_ETH_WINNERS, "all ETH winners are distinct cold addresses");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.battleEntries, 0, "the battle never rides the daily stage");
        assertFalse(t.bafArmed, "the latch waits for the sealing ticket stage");
    }
}

/// @notice HEADLINE: 105 ETH winners and ticket pricing, then 192 tickets with the target-met latch
///         and BAF arm, over populated minted-ahead boards and unminted queues.
contract PurchaseDailyWorstCase is PurchaseDailyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _label() internal pure override returns (string memory) { return "LATCH_BAF"; }
}

/// @notice SPLIT (a): ETH + ticket legs only — no minted-ahead decoys, no unminted queues, no latch.
contract PurchaseDailyEthTicketsOnly is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, 0, 0, NEXT_POOL_QUIET, PREV_POOL_OPEN25));
    }

    function test_PurchaseDaily_49Eth_Tickets_NoLatch_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_ETH_TICKETS_ONLY (stage 6): 105 ETH, ticket pricing", used, t);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "105 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins + t.battleEntries, 0, "no coin draw rides the daily stage");

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 192 tickets", false);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_TICKET_STAGE_GAS", ticketUsed);
    }
}

/// @notice Fresh-word stress: the word applies alone (stage 18), the battle its request locked runs
///         its own steps, then stage 6 pays the ETH leg and stage 15 the tickets. Each transaction
///         is measured alone.
abstract contract PurchaseDailyWithRngApplyStage is PurchaseDailyStage, FreshWordLeg {
    function setUp() public override {
        PurchaseDailySeeder.Shape memory s =
            _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, uint128(_prev() + 1 ether), _prev());
        _seedFresh(s);
        _armFreshWord(s.word, 400);
    }

    function test_PurchaseDaily_49Eth_TicketPricing_Measured() public override {
        (uint256 applyUsed,) = _applyWord(false, EIP7825_TX_GAS_CAP);
        emit log_named_uint(string.concat("PURCHASE_DAILY_WORD_APPLY_GAS_", _label()), applyUsed);
        _driveBattle(STAGE_PURCHASE_BATTLE);

        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("PURCHASE_DAILY_AFTER_RNG_APPLY (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TRUE_CEILING_GAS_", _label()), used);
        _assertStage(t);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 192 tickets + latch + BAF arm", true);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TRUE_CEILING_TICKET_STAGE_GAS_", _label()), ticketUsed);
    }
}

/// @notice TRUE CEILING of each purchase-day transaction with a fresh word and a 26-award battle.
contract PurchaseDailyWithRngApply is PurchaseDailyWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _label() internal pure override returns (string memory) { return "LATCH_BAF"; }
}

/// @notice Level one pays its 50 trait shares in stage 6, which also seals the day: level one has
///         no ticket leg. The seeded day locks no battle.
abstract contract PurchaseDailyLevelOneStage is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public virtual {
        _seed(_shapeLevelOne(_prev(), true));
    }

    function test_LevelOne_TraitDraw50Shares_Latch_Measured() public virtual {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("LEVEL1_TRAIT_DRAW (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("LEVEL1_TRAIT_DRAW_GAS_", _label()), used);
        _assertLevelOne(t);
    }

    function _assertLevelOne(Tally memory t) internal {
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the level-1 purchase daily ran");
        assertEq(t.ethWins + t.ticketWins, 0, "no ETH / ticket leg at level 1");
        assertEq(t.battleEntries, 0, "the battle never rides the trait draw");
        assertEq(t.flipWins, COIN_DRAW_SHARES, "the trait draw paid the full 50-share cap");
        emit log_named_uint("  level1_distinct_recipients", t.coinDistinct);
        // The trait draw samples with replacement: allow a stray repeat.
        assertGe(
            t.coinDistinct,
            COIN_DRAW_SHARES - 1,
            "all but a stray trait-draw repeat are distinct cold wallets"
        );
        (,, bool lastPurchase,,) = game.purchaseInfo();
        assertTrue(lastPurchase, "the trait-draw stage seals level one's day");
        assertFalse(game.rngLocked(), "the sealing stage unlocks");
    }
}

/// @notice Level 1 at the maximum budget: the trait draw's 50 shares saturate.
contract PurchaseDailyLevelOneSaturated is PurchaseDailyLevelOneStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _label() internal pure override returns (string memory) { return "S50_LATCH"; }
}

/// @notice Level one with a fresh word: stage 18 applies it, the 250-award battle its request locked
///         runs its own steps, then stage 6 pays the trait draw and seals.
abstract contract PurchaseDailyLevelOneWithRngApplyStage is PurchaseDailyLevelOneStage, FreshWordLeg {
    function setUp() public override {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(_prev(), true);
        _seedFresh(s);
        _armFreshWord(s.word, 400);
    }

    function test_LevelOne_TraitDraw50Shares_Latch_Measured() public override {
        (uint256 applyUsed,) = _applyWord(false, EIP7825_TX_GAS_CAP);
        emit log_named_uint(string.concat("LEVEL1_WORD_APPLY_GAS_", _label()), applyUsed);
        _driveBattle(STAGE_PURCHASE_BATTLE);

        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("LEVEL1_TRAIT_DRAW_AFTER_RNG_APPLY (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("LEVEL1_TRAIT_DRAW_TRUE_CEILING_GAS_", _label()), used);
        _assertLevelOne(t);
    }
}

contract PurchaseDailyLevelOneWithRngApplySaturated is PurchaseDailyLevelOneWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _label() internal pure override returns (string memory) { return "S50_LATCH"; }
}
