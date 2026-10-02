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
import {DayOneSeeder, DayOneFixture} from "./JackpotDayOneWorstCase.t.sol";

/// @title PurchaseDailyWorstCase — transaction costs of the purchase-phase daily stages.
/// @notice Stage 6 pays 49 ETH winners (or level one's 50 trait shares) and prices tickets.
///         Stage 15 pays up to 120 tickets and seals the day; without tickets, stage 6 seals it.
///         A fresh daily request also locks the day's jackpot battle: once the VRF word lands it
///         applies alone (stage 18), the battle runs its own stage-17 steps, and only then do
///         stages 6 and 15 run. The held RNG lock freezes inputs between transactions. Seeded
///         days record their word without a request, so they lock no battle; the word-apply
///         variants drive the real request, VRF callback and battle.
/// @dev All stages use the real protocol. Run with `FOUNDRY_ISOLATE=true forge test` so calls later
///      in a test have fresh transaction access lists, matching real keeper transactions.
///      Gas includes intrinsic cost; samples are not exhaustive maximum proofs.
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
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
        levelPrizePool[s.lvl] = s.prevPool;
        currentPrizePool = uint128(100 ether);
        _setPrizePools(s.nextPool, s.futurePool);

        // The empty-board split excludes protocol participation too: genesis deity passes supply
        // virtual bucket entries. A level-1 trait draw excludes them as well — a deity lands on
        // VAULT / sDGNRS, whose seat is refused (cheaper than a fresh seat).
        if (s.bonusHolders == 0 || s.traitHolders != 0) {
            deityBySymbol[VAULT_DEITY_SYMBOL] = address(0);
            deityBySymbol[SDGNRS_DEITY_SYMBOL] = address(0);
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
            if (ticketOwners.length == 0) _registerEntryOwner(address(1), L);
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
                    _tqAppend(_tqFarFutureKey(c), uint32(_registerEntryOwner(address(b + uint160(i + 1)), c) >> OWNER_IDX_SHIFT));
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

/// @dev The day-1 jackpot-phase seeder with the same un-record door.
contract DayOneUnrecordedSeeder is DayOneSeeder {
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

/// @dev The rngGate word-apply leg, driven for real: book the craps table's 7-day action window (so
///      openBonusDay draws a high budget and posts stakes), settle Coinflip through day-1 (so the
///      measured sDGNRS settle walks exactly one day, the steady-state shape, not the day-400 jump),
///      fire the day's VRF request from the real advanceGame (which locks the day's jackpot battle),
///      and fulfil it on the mock coordinator. The NEXT advanceGame applies the word alone, stage 18
///      (_applyDailyRng, coinflip.processCoinflipPayouts, quests.rollDailyQuest, craps openBonusDay,
///      _finalizeLootboxRng); the battle's steps follow, then the day's own stages.
abstract contract FreshWordLeg is DeployProtocol {
    uint8 internal constant STAGE_RNG_REQUESTED_ = 1;
    uint8 internal constant STAGE_RNG_APPLIED_ = 18;
    uint256 internal constant CRAPS_DAY_STAKED_SLOT = 10; // CrapsBattle `_dayStaked` (forge inspect)
    /// @dev Every jackpot battle transaction stays within 10M (JackpotMergeAdvance pins its shapes).
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

        uint256 before = mockVRF.lastRequestId();
        vm.recordLogs();
        game.advanceGame();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint8 st = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) (st,) = abi.decode(logs[i].data, (uint8, uint24));
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
        return _countTopic(logs, keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)"))
            + _countTopic(logs, keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)"));
    }

    /// @dev One advance tx at the EIP-7825 limit less intrinsic, through the mineFlip router when
    ///      `router`: its stage, its gas (intrinsic included) and its logs.
    function _advanceTx(bool router) internal returns (uint8 stage, uint256 used, Vm.Log[] memory logs) {
        vm.recordLogs();
        if (router) game.mineFlip{gas: 16_777_216 - 21_064}();
        else game.advanceGame{gas: 16_777_216 - 21_064}();
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

    /// @dev The fresh word's apply transaction, stage 18 alone: the coinflip settlement and the craps
    ///      day it opens, no daily leg and no battle step. Returns its gas (intrinsic included) and logs.
    function _applyWord(bool router, uint256 limit) internal returns (uint256 used, Vm.Log[] memory logs) {
        uint8 stage;
        (stage, used, logs) = _advanceTx(router);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(logs);
        emit log_named_uint("word_apply_tx_incl_intrinsic", used);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        assertEq(stage, STAGE_RNG_APPLIED_, "the fresh word applies alone");
        assertEq(_dailyLegLogs(logs), 0, "the word-apply tx pays no daily leg");
        assertEq(
            _countTopic(logs, keccak256("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)")),
            0,
            "the word-apply tx draws no battle entry"
        );
        assertGe(cfLogs, 1, "coinflip.processCoinflipPayouts ran in the word-apply tx");
        assertGe(crLogs, 8, "craps openBonusDay opened the day's windows in the word-apply tx");
        assertLt(used, limit, "the word-apply tx exceeds its limit");
    }

    /// @dev Steps the day's locked jackpot battle to completion. Each step is its own `battleStage`
    ///      transaction, pays no ETH or ticket winner, and stays within 10M.
    function _driveBattle(uint8 battleStage) internal returns (uint256 steps) {
        IJackpotBattle battle = IJackpotBattle(address(crapsBattle));
        uint256 largest;
        (,,, bool complete) = battle.jackpotProgress();
        while (!complete) {
            assertLt(steps++, 40, "the jackpot battle stalled");
            (uint8 stage, uint256 used, Vm.Log[] memory logs) = _advanceTx(false);
            assertEq(stage, battleStage, "a battle step runs from its own stage");
            assertEq(_dailyLegLogs(logs), 0, "a battle step shares no daily leg");
            assertLe(used, BATTLE_TX_LIMIT, "a jackpot battle tx crossed 10M");
            if (used > largest) largest = used;
            (,,, complete) = battle.jackpotProgress();
        }
        assertTrue(game.rngLocked(), "the day's own stages still hold the lock");
        emit log_named_uint("jackpot_battle_steps", steps);
        emit log_named_uint("jackpot_battle_largest_tx_incl_intrinsic", largest);
    }
}

/// @dev Shared measurement seam: warp, etch-seed-restore, drive the live advanceGame, classify winners.
abstract contract PurchaseDailyFixture is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this is a permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev The 10M soft design target the drains are sized to (USER dual bound).
    uint256 internal constant GAS_TARGET = 10_000_000;
    /// @dev Intrinsic cost of a zero-arg advanceGame() tx: 21,000 base + 4 non-zero calldata bytes.
    uint256 internal constant INTRINSIC = 21_064;

    bytes32 internal constant ETH_WIN_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant BATTLE_ENTRY_SIG = keccak256("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)");
    bytes32 internal constant BAF_ARMED_SIG = keccak256("BafDrawArmed(uint24)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint8 internal constant STAGE_PURCHASE_BATTLE = 17;
    uint16 internal constant PURCHASE_ETH_WINNERS = 49; // 24 + 16 + 8 + 1
    uint16 internal constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;
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
    ///      - FUTURE_POOL 5000 ETH -> the drip covers 49 ETH winners and >= 120 whole tickets.
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
        // This word pays 49 distinct ETH and 120 distinct ticket recipients at full caps.
        s.word = _word("purchase-daily-eight-groups");
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

    /// @dev One advanceGame tx, called with the EIP-7825 limit less intrinsic (so an over-cap
    ///      composition reverts out of gas rather than passing). `used` INCLUDES the 21,064 intrinsic.
    function _measure() internal returns (uint256 used, Tally memory t) {
        vm.recordLogs();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        used = _transactionGas();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        delete lastLogs;
        for (uint256 i; i < logs.length; ++i) lastLogs.push(logs[i]);
        address[] memory ethW = new address[](PURCHASE_ETH_WINNERS + 8);
        address[] memory tkW = new address[](PURCHASE_PHASE_TICKET_MAX_WINNERS + 8);
        address[] memory coinW = new address[](COIN_DRAW_SHARES + 8);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == ETH_WIN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[1])));
                if (_pushDistinct(ethW, t.ethWins, w)) ++t.ethDistinct;
                ++t.ethWins;
            } else if (t0 == TICKET_WIN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[1])));
                if (_pushDistinct(tkW, t.ticketWins, w)) ++t.ticketDistinct;
                ++t.ticketWins;
            } else if (t0 == FLIP_WIN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[1])));
                if (_pushDistinct(coinW, t.flipWins, w)) ++t.coinDistinct;
                ++t.flipWins;
            } else if (t0 == BATTLE_ENTRY_SIG) {
                ++t.battleEntries;
            } else if (t0 == BAF_ARMED_SIG) {
                t.bafArmed = true;
            } else if (t0 == ADVANCE_SIG) {
                (t.stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        emit log_named_uint("tx_gas_incl_intrinsic", used);
        emit log_named_uint("headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
        emit log_named_uint("distance_to_10M_target", used < GAS_TARGET ? GAS_TARGET - used : 0);
        emit log_named_uint("over_10M_target_by", used > GAS_TARGET ? used - GAS_TARGET : 0);
    }

    /// @dev With isolation, Foundry includes calldata intrinsic in the top-level CALL cost.
    ///      Otherwise add it once. Read the call cost before any further contract calls.
    function _transactionGas() internal view returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += INTRINSIC;
    }

    /// @dev Appends `w` at `n` and reports whether it was unseen among the first `n` (O(n^2), n <= 120).
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

    function _assertCaps(uint256 used) internal {
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }

    /// @dev The priced ticket leg: the next advance, same word, 120 distinct cold winners, sealing the day.
    function _measureTicketStage(string memory label, bool expectBaf) internal returns (uint256 used) {
        Tally memory tk;
        (used, tk) = _measure();
        _emitTally(label, used, tk);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ticketDistinct, PURCHASE_PHASE_TICKET_MAX_WINNERS, "all ticket winners are distinct cold addresses");
        assertEq(tk.ethWins + tk.flipWins + tk.battleEntries, 0, "only the ticket leg rides the ticket stage");
        assertEq(tk.bafArmed, expectBaf, "the sealing stage latches (and arms the BAF draw) iff the target is met");
        _assertCaps(used);
    }
}

/// @notice The purchase sequence: 49 ETH plus ticket pricing, then 120 tickets and the target-met
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
        _assertCaps(used);
        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets + latch + BAF arm", true);
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
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "the ETH leg paid all 49 fixed-bucket winners");
        assertEq(t.ethDistinct, PURCHASE_ETH_WINNERS, "all ETH winners are distinct cold addresses");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.battleEntries, 0, "the battle never rides the daily stage");
        assertFalse(t.bafArmed, "the latch waits for the sealing ticket stage");
    }
}

/// @notice HEADLINE: 49 ETH winners and ticket pricing, then 120 tickets with the target-met latch
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
        _emitTally("PURCHASE_DAILY_ETH_TICKETS_ONLY (stage 6): 49 ETH, ticket pricing", used, t);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins + t.battleEntries, 0, "no coin draw rides the daily stage");
        _assertCaps(used);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", false);
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
        _assertCaps(used);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets + latch + BAF arm", true);
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
        _assertCaps(used);
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
        _assertCaps(used);
    }
}

contract PurchaseDailyLevelOneWithRngApplySaturated is PurchaseDailyLevelOneWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _label() internal pure override returns (string memory) { return "S50_LATCH"; }
}

/// @notice TRUE CEILING of the jackpot-phase day-1 ETH stage with a fresh word: the word applies alone
///         (stage 18), the battle its request locked runs its stage-16 steps, then stage 10 pays 305
///         ETH winners and resolves the golden grand. Each transaction is measured alone.
contract JackpotDayOneWithRngApply is DayOneFixture, FreshWordLeg {
    uint8 internal constant STAGE_JACKPOT_BATTLE = 16;

    function setUp() public {
        uint256 word = _allGoldWord("jackpot-day-one-gold");
        _deployProtocol();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(word);
        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(DayOneUnrecordedSeeder).runtimeCode);
        DayOneUnrecordedSeeder(payable(address(game))).seedDayOne(LVL, word, mainT, BASE, ETH_HOLDERS, EB_HOLDERS, true);
        DayOneUnrecordedSeeder(payable(address(game))).unrecordWord();
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
        _armFreshWord(word, 400);
    }

    function test_DayOne_305Eth_AllGold_GoldenGrand_WithRngApplyLeg_Measured() public {
        (uint256 applyUsed,) = _applyWord(false, EIP7825_TX_GAS_CAP);
        emit log_named_uint("JACKPOT_DAY1_WORD_APPLY_GAS", applyUsed);
        _driveBattle(STAGE_JACKPOT_BATTLE);

        (uint8 stage, uint256 used, Vm.Log[] memory logs) = _advanceTx(false);
        uint256 ethWins;
        bool grand;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == ETH_WIN_SIG) {
                ++ethWins;
            } else if (t0 == GOLDEN_WIN_SIG) {
                (,, bool g,,,,) = abi.decode(logs[i].data, (uint8, uint8, bool, uint256, uint256, uint256, uint256));
                grand = g;
            }
        }
        emit log_string("DAY1_AFTER_RNG_APPLY tx (stage 10): 305 ETH, all-gold, golden grand");
        emit log_named_uint("  advance_gas", used);
        emit log_named_uint("  stage", stage);
        emit log_named_uint("  eth_wins", ethWins);
        emit log_named_uint("headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
        emit log_named_uint("JACKPOT_DAY1_ETH_STAGE_TRUE_CEILING_GAS", used);

        assertEq(stage, STAGE_JACKPOT_DAILY_STARTED, "the day-1 ETH stage follows the battle");
        assertEq(ethWins, DAILY_ETH_MAX_WINNERS, "305 ETH winners");
        assertTrue(grand, "golden grand resolved");
        assertLt(used, EIP7825_TX_GAS_CAP, "TRUE CEILING: the day-1 ETH stage clears EIP-7825");
    }
}
