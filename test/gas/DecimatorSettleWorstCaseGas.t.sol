// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {DecimatorWalkHarness} from "./DecimatorSettleGas.t.sol";

/// @dev Etched over the Game during setup only: the production ticket sink and the queue views, so a
///      target level's queue can be filled the way other buyers fill it.
contract DecimatorTargetLevelHarness is DegenerusGameStorage {
    function queueEntries(address buyer, uint24 lvl, uint32 entries) external {
        _queueEntries(buyer, lvl, entries, false);
    }

    /// @dev The queue key a box's ticket flush appends to at `lvl` (see _queueEntries).
    function appendKey(uint24 lvl) public view returns (uint24) {
        return lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
    }

    function queueLength(uint24 lvl) external view returns (uint256) {
        return ticketQueue[appendKey(lvl)].length;
    }

    /// @dev The queue word the next append at `lvl` writes.
    function nextQueueWord(uint24 lvl) external view returns (uint256) {
        uint256[] storage q = ticketQueue[appendKey(lvl)];
        return _tqWordAt(q, q.length);
    }

    function registryLength(uint24 lvl) external view returns (uint256) {
        return lvlEntryOwner[lvl].length;
    }
}

/// @title DecimatorSettleWorstCaseGas — calibration pin for the decimator walk's outcome pricing
/// @notice mineFlip's decimator leg charges each settle after it runs, by what it did:
///           DEC_SETTLE_UNITS, + DEC_WHALE_UNITS when whole half-passes defer, + the box's
///           `_boxWorkUnits` when a box resolves (BOX_BASE_UNITS, BOX_LANE_UNITS per ticket level,
///           BOX_DGNRS/FLIP/WWXRP/PASS_UNITS per paid lane, BOX_ACTIVITY_UNITS per activity award),
///         and DEC_CALL_UNITS once per call for what a batch touches once.
///         The prices are in-batch: each branch group of fresh winners is settled cold, one winner and
///         then all of them from the same state; the difference is the branch's marginal, and a mixed
///         group (one winner of each branch) less its members' marginals is the once-per-call cost.
///         Every multi-settle call must fit the units the walk charged for it (gas <= units x 4,700,
///         the call price included once), the walk must charge the prices mirrored here (K_*), and the
///         test derives, from the groups, the prices they imply. Full mineFlip calls must stay within
///         10M, and a typical one must use most of its budget.
///
///         Every group is the heaviest reachable state for its branch:
///           - bucket 5 (the floor below x00 levels): the sealed score is above EV-neutral, so the
///             box draws on the per-level EV cap, a first write; a score that high takes minting, so
///             mintPacked_ is set, and the burn's own quest leg (FLIP -> Quests.handleDecimator) has
///             synced the quest slot on the burn day;
///           - no prior winnings: balancesPacked and whalePassClaims are first writes;
///           - whale groups: a 6.7 ETH lootbox half (two half-passes + a 2.2 ETH box); no-whale groups:
///             the same 2.2 ETH box without deferral; dust: three half-passes and a remainder below
///             0.01 ETH, so no box;
///           - tickets at the open level while its write queue is empty (the length is a first write
///             too); a far level whose queue length sits on a word boundary (every far level already
///             holds the two protocol deities, registered at levels 1-100 and extended to level + 100
///             at every transition, so a far registry is never empty); a far level whose word is open;
///           - the day-pass roll on the first seat reserved for tomorrow (the day counter is a first
///             write) and on a later seat; each spin roll with and without a payout;
///           - the activity award after the longest re-sync the groups can build: 255 shields, a
///             streak anchored at the burn, the settle 256+ rolled quest days later (256 missed days
///             walked, every shield spent, the streak reset), and as an afking subscriber funded by
///             an operator (the award re-enters the Game's afking module and the own balance is 0);
///           - the whale-pass boon on a no-whale winner (a first write), slot-writing boons on empty
///             and on swept boon slots, the quest-shield boon, and no boon;
///           - with and without expired deity boons in all nine categories a deity can issue
///             (issued on nine earlier days), which the boon draw's expiry sweep rewrites.
///         Winners are chosen by address so the committed box seed lands each branch; every settle's
///         outcome is read back from its own events and checked against its spec.
contract DecimatorSettleWorstCaseGas is DeployProtocol {
    // ---- Walk-unit prices (mirror of DegenerusGameDecimatorModule / DegenerusGameLootboxModule) ----
    uint256 internal constant K_CALL = 39;
    uint256 internal constant K_SETTLE = 8;
    uint256 internal constant K_WHALE = 5;
    uint256 internal constant K_BASE = 9;
    uint256 internal constant K_SPIN = 2;
    uint256 internal constant K_BOON = 6;
    uint256 internal constant K_SWEEP = 2;
    uint256 internal constant K_LANE = 18;
    uint256 internal constant K_DGNRS = 7;
    uint256 internal constant K_FLIP = 6;
    uint256 internal constant K_WWXRP = 5;
    uint256 internal constant K_PASS = 16;
    uint256 internal constant K_ACTIVITY = 16;

    /// @dev The activity award's quest re-sync reads one rolled-day bitmap word per 256 days until it
    ///      has counted 256 misses. The groups walk them over two words; a longer game can spread 256
    ///      rolled days thinner, one per 30 days at the sparsest (a longer gap trips the liveness
    ///      deadman), so up to 30 more words the groups cannot build. The words are shared by every
    ///      winner's re-sync, so a call reads each cold once (the call price) and warm after (the
    ///      activity price).
    uint256 internal constant LONG_RESYNC_WORDS = 30;
    uint256 internal constant RESYNC_WORD_COLD_GAS = 2_100 + 300;
    uint256 internal constant RESYNC_WORD_WARM_GAS = 100 + 300;
    /// @dev Levels whose write queue can be empty at once: the open level, and the next one while the
    ///      last purchase day latches it into the mint window.
    uint256 internal constant EMPTY_WRITE_QUEUES = 2;

    // ---- Storage slots (forge inspect <contract> storageLayout) ----
    uint256 internal constant SLOT_POOLS_1 = 1;
    uint256 internal constant SLOT_MINT_PACKED = 9;
    uint256 internal constant SLOT_BOON_PACKED = 50;
    uint256 internal constant SLOT_SUB_OF = 52;
    uint256 internal constant SLOT_SUBSCRIBER_INDEX = 55;
    uint256 internal constant QUESTS_SLOT_PLAYER_STATE = 1;
    uint256 internal constant CRAPS_SLOT_DAY_TICKETS = 7;

    // ---- Walk ----
    /// @dev The decimator leg's own walk budget in mineFlip (GameAfkingModule.DEC_WALK_BUDGET).
    uint256 internal constant DEC_WALK_BUDGET = 2_030;
    /// @dev A resumed walk's round probe and list-length read, 1 unit each.
    uint256 internal constant RESUME_LEAD_UNITS = 2;
    /// @dev A walk entering the round: the probe and the length reads of denominators 2..DENOM.
    uint256 internal constant FIRST_LEAD_UNITS = 1 + (DENOM - 1);
    uint256 internal constant UNIT_GAS = 4_700;
    uint256 internal constant TX_INTRINSIC = 21_000;
    uint256 internal constant REALISTIC_CEILING = 10_000_000;
    /// @dev A typical full call must use most of its budget.
    uint256 internal constant TYPICAL_FLOOR = 8_000_000;

    // ---- The constructed round ----
    uint24 internal constant LVL = 5;
    uint8 internal constant DENOM = 5;
    uint16 internal constant SCORE = 250; // ActivityCurveLib.minScoreForBucket(5)
    uint256 internal constant MULT_1X = 10_000;
    bytes32 internal constant DECIMATOR_BOX_TAG = keccak256("degenerus.decimator.box");
    uint256 internal constant BOX_WWXRP_SPIN_TAG = 0x57777872705370696e;
    uint256 internal constant BOX_FLIP_SPIN_TAG = 0x4275726e69655370696e;
    /// @dev Quest days between the burn and the settle: past the 256 misses 255 shields can absorb.
    uint256 internal constant SETTLE_DELAY_DAYS = 262;
    /// @dev One minted level (mintPacked_ level count), standing in for the activity behind bucket 5.
    uint256 internal constant MINT_HISTORY = uint256(1) << 24;
    uint256 internal constant FULL_WINNERS = 45;
    uint256 internal constant LANE_WINNERS = 60;
    uint256 internal constant TYPICAL_WINNERS = 150;

    // ---- Win sizes ----
    uint8 internal constant NO_WHALE = 0; // 4.4 ETH: a 2.2 ETH box
    uint8 internal constant WHALE = 1; // 13.4 ETH: two half-passes and a 2.2 ETH box
    uint8 internal constant DUST = 2; // 13.51 ETH: three half-passes, no box
    uint8 internal constant TYPICAL = 3; // 2 ETH: a 1 ETH box

    // ---- Box rolls (_resolveLootboxRoll, allowEthSpin = false) ----
    uint8 internal constant PATH_TICKETS = 0;
    uint8 internal constant PATH_DGNRS = 1;
    uint8 internal constant PATH_WWXRP_SPIN = 2;
    uint8 internal constant PATH_FLAT_FLIP = 3;
    uint8 internal constant PATH_PASSES = 4;
    uint8 internal constant PATH_FLIP_SPINS = 5;
    uint8 internal constant PATH_ANY = 255;
    uint8 internal constant PAYS = 1;
    uint8 internal constant PAYS_NOTHING = 2;

    // ---- Boon draws (_boonFromRoll bands) ----
    uint8 internal constant BOON_NONE = 0;
    uint8 internal constant BOON_ACTIVITY = 1;
    uint8 internal constant BOON_QUEST_SHIELD = 2;
    uint8 internal constant BOON_COINFLIP = 3;
    uint8 internal constant BOON_WHALE_PASS = 4;
    uint8 internal constant BOON_DEITY_PASS = 5;
    uint8 internal constant BOON_OTHER = 6;
    uint8 internal constant BOON_ANY = 255;

    // ---- Winner history ----
    uint8 internal constant PLAIN = 0;
    uint8 internal constant RICH = 1; // + 255 shields and a streak anchored at the burn
    uint8 internal constant RICH_AFK = 2; // + a live operator-funded afking run

    // ---- Target-offset selection for a ticket roll ----
    int256 internal constant OFFSET_ANY = -1;
    /// @dev A far offset (1..50) not yet taken by this set.
    int256 internal constant OFFSET_NEW = -2;
    uint256 internal constant TARGET_OFFSETS = 51;

    bytes32 internal constant DEC_CLAIMED_SIG = keccak256("DecimatorClaimed(address,uint24,uint256,uint256,uint256)");
    bytes32 internal constant ENTRIES_QUEUED_SIG = keccak256("EntriesQueued(address,uint24,uint32)");
    bytes32 internal constant DGNRS_BATCH_SIG = keccak256("LootBoxDgnrsBatch(address,uint256,uint256)");
    bytes32 internal constant FLIP_STAKE_SIG = keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");
    bytes32 internal constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant PASSES_SIG = keccak256("LootBoxCrapsPasses(address,uint32,uint32,uint24)");
    bytes32 internal constant BOON_CONSUMED_SIG = keccak256("BoonConsumed(address,uint8,uint16)");
    bytes32 internal constant SHIELD_USED_SIG = keccak256("QuestStreakShieldUsed(address,uint16,uint16,uint24)");
    bytes32 internal constant BOON_REWARD_SIG = keccak256("LootBoxReward(address,uint8,uint256,uint256)");
    bytes32 internal constant WHALE_PASS_BOON_SIG =
        keccak256("LootBoxWhalePassJackpot(address,uint256,uint24,uint32,uint24,uint24)");
    bytes32 internal constant BOON_DISCARDED_SIG = keccak256("BoonDiscarded(address,uint8)");
    bytes32 internal constant BOX_SPIN_SIG = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 64;
    uint256 private constant MAX_GRIND = 5_000_000;

    struct Row {
        uint8 size;
        uint8 path;
        uint8 pay;
        uint8 boon;
        int256 offset;
        bool sweep;
        uint8 history;
        uint256 count;
        string label;
    }

    /// @dev What one settle did, read from its events.
    struct Comp {
        bool whale;
        bool box;
        uint256 lanes;
        bool dgnrs;
        bool flip;
        bool wwxrp;
        bool pass;
        uint256 activity;
        uint256 fullResync;
        uint256 boons;
        uint256 spins;
        bool swept;
    }

    struct Prices {
        uint256 call;
        uint256 settle;
        uint256 whale;
        uint256 base;
        uint256 spin;
        uint256 boon;
        uint256 sweep;
        uint256 lane;
        uint256 dgnrs;
        uint256 flip;
        uint256 wwxrp;
        uint256 pass;
        uint256 activity;
    }

    uint256 private _lastFulfilledReqId;
    address internal keeper;
    uint24 internal curLevel;
    uint24 internal burnDay;
    uint24 internal today;
    uint256 internal drawWord;
    uint256 internal boxWord;
    uint8 internal winSub;
    uint256 internal boonChance;
    uint256 private _cursor;

    address[] internal rowWinners;
    uint256[] internal rowGroup;
    uint256[] internal groupStart;
    bool[51] internal rowUsed;
    address[] internal fullWinners;
    bool[51] internal fullUsed;
    address[] internal oneWinner;
    bool[51] internal oneUsed;
    address[] internal laneWinners;
    bool[51] internal laneUsed;
    address[] internal typicalWinners;

    // =====================================================================
    // Setup
    // =====================================================================

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("dec_wc_keeper");
        // The burn day: a few sealed days after deploy.
        vm.warp(block.timestamp + 12 days);
        _settleGame(uint256(keccak256("dec-wc-settle")));
        require(!game.advanceDue() && !game.rngLocked(), "setup: advance pending");

        curLevel = game.level() + 1;
        burnDay = game.currentDayView();
        drawWord = uint256(keccak256("dec-wc-draw"));
        uint32 roundWord = uint32(uint256(keccak256(abi.encode(drawWord, DECIMATOR_BOX_TAG))));
        boxWord = uint256(keccak256(abi.encode(uint256(roundWord), DECIMATOR_BOX_TAG, LVL)));
        winSub = uint8(uint256(keccak256(abi.encodePacked(drawWord, DENOM))) % DENOM);
        boonChance = _boonTotalChance(2.2 ether);

        // Spin outcomes are screened through the production Degenerette code, run in the Game's
        // context the way the lootbox module delegatecalls it.
        bytes memory original = address(game).code;
        vm.etch(address(game), ContractAddresses.GAME_DEGENERETTE_MODULE.code);
        _grindRows();
        _grindFullCalls();
        vm.etch(address(game), original);
        for (uint256 i; i < TYPICAL_WINNERS; ++i) {
            typicalWinners.push(_inWinningList(i));
        }

        for (uint256 i; i < rowWinners.length; ++i) {
            _installHistory(rowWinners[i], _specOf(i).history);
        }
        for (uint256 i; i < fullWinners.length; ++i) {
            _installHistory(fullWinners[i], RICH_AFK);
        }
        _installHistory(oneWinner[0], RICH_AFK);
        for (uint256 i; i < typicalWinners.length; ++i) {
            _installHistory(typicalWinners[i], PLAIN);
        }
        for (uint256 i; i < laneWinners.length; ++i) {
            _installHistory(laneWinners[i], PLAIN);
        }

        // The settle comes SETTLE_DELAY_DAYS quest days after the burns, one sealed day at a time.
        // (A local clock: via-IR may reuse one block.timestamp read across the loop.)
        uint256 t = block.timestamp;
        for (uint256 d; d < SETTLE_DELAY_DAYS; ++d) {
            t += 1 days;
            vm.warp(t);
            _settleGame(uint256(keccak256(abi.encode("dec-wc-day", d))));
        }
        game.openBoxes(1_000);
        _quietCrapsTable();
        require(!game.advanceDue() && !game.rngLocked(), "setup: advance pending");
        require(game.level() + 1 == curLevel, "setup: level moved");
        today = game.currentDayView();
        require(today >= burnDay + 257, "setup: settle delay");
        require(_dayTickets(today + 1) == 0, "setup: tomorrow already seated");
        _fillTargetQueuesToWordBoundary();

        for (uint256 i; i < rowWinners.length; ++i) {
            if (_specOf(i).history == RICH_AFK) _startAfkingRun(rowWinners[i]);
        }
        for (uint256 i; i < fullWinners.length; ++i) {
            _startAfkingRun(fullWinners[i]);
        }
        _startAfkingRun(oneWinner[0]);
    }

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

    /// @dev The burner's standing at the burn day: minting behind its bucket; for RICH, 255 quest shields
    ///      and a streak anchored on the burn day (the Game's shield and streak doors); then the burn's
    ///      own quest leg (FLIP.decimatorBurn -> Quests.handleDecimator), which syncs the quest slot.
    function _installHistory(address p, uint8 history) internal {
        vm.store(address(game), keccak256(abi.encode(p, SLOT_MINT_PACKED)), bytes32(MINT_HISTORY));
        require(game.mintPackedFor(p) == MINT_HISTORY, "mintPacked slot");
        if (history != PLAIN) {
            vm.prank(ContractAddresses.GAME);
            quests.awardQuestStreakShield(p, 255);
            vm.prank(ContractAddresses.GAME);
            quests.awardQuestStreakBonus(p, 100, burnDay);
        }
        vm.prank(ContractAddresses.COIN);
        quests.handleDecimator(p, 1_000 ether);
    }

    /// @dev A live afking run funded by an operator: the Quests afking flag, the subscriber index and the
    ///      run's start day. The award then routes the streak bonus into the run (recordAfkingSecondary).
    function _startAfkingRun(address p) internal {
        bytes32 q = keccak256(abi.encode(p, QUESTS_SLOT_PLAYER_STATE));
        vm.store(address(quests), q, bytes32(uint256(vm.load(address(quests), q)) | (uint256(1) << 104)));
        vm.store(address(game), keccak256(abi.encode(p, SLOT_SUBSCRIBER_INDEX)), bytes32(uint256(1)));
        bytes32 s = keccak256(abi.encode(p, SLOT_SUB_OF));
        vm.store(address(game), s, bytes32(uint256(vm.load(address(game), s)) | (uint256(burnDay) << 128)));
    }

    /// @dev Other buyers' tickets at every reachable target level, until the level's next append opens a
    ///      new queue word: the queue length is a multiple of eight and the word at it is empty.
    function _fillTargetQueuesToWordBoundary() internal {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(DecimatorTargetLevelHarness).runtimeCode);
        DecimatorTargetLevelHarness h = DecimatorTargetLevelHarness(address(game));
        for (uint256 o; o < TARGET_OFFSETS; ++o) {
            uint24 lvl = curLevel + uint24(o);
            require(h.registryLength(lvl) >= 2, "setup: protocol deities registered");
            for (uint256 j; h.queueLength(lvl) % 8 != 0 || h.nextQueueWord(lvl) != 0; ++j) {
                h.queueEntries(address(uint160(uint256(keccak256(abi.encode("dec-wc-buyer", lvl, j))))), lvl, 4);
            }
        }
        require(h.queueLength(curLevel) == 0, "setup: open-level queue empty");
        vm.etch(address(game), original);
    }

    /// @dev A target level's queue length, read through the target-level harness over whatever code the
    ///      Game holds.
    function _queueLengthAt(uint256 offset) internal returns (uint256 len) {
        bytes memory current = address(game).code;
        vm.etch(address(game), type(DecimatorTargetLevelHarness).runtimeCode);
        len = DecimatorTargetLevelHarness(address(game)).queueLength(curLevel + uint24(offset));
        vm.etch(address(game), current);
    }

    function _dayTickets(uint256 day) internal view returns (uint256) {
        return uint32(uint256(vm.load(ContractAddresses.CRAPS, keccak256(abi.encode(day * 8, CRAPS_SLOT_DAY_TICKETS)))));
    }

    function _winAmount(uint8 size) internal pure returns (uint256) {
        if (size == WHALE) return 13.4 ether;
        if (size == DUST) return 13.51 ether;
        if (size == TYPICAL) return 2 ether;
        return 4.4 ether;
    }

    /// @dev Burns weighted so each winner's pro-rata share is exactly its win: weight is proportional to
    ///      the win, and the pool is the sum of the wins.
    function _burn(address player, uint8 size) internal returns (uint256 win) {
        win = _winAmount(size);
        vm.prank(ContractAddresses.COIN);
        uint8 bucketUsed = game.recordDecBurn(player, LVL, DENOM, win * 1_000, MULT_1X);
        require(bucketUsed == DENOM, "burn: bucket");
    }

    /// @dev The draw as the jackpot phase runs it, plus the claimablePool booking its caller makes.
    function _draw(uint256 poolWei) internal {
        vm.prank(address(game));
        uint256 returned = game.runDecimatorJackpot(poolWei, LVL, drawWord);
        require(returned == 0, "draw: no winners");
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_POOLS_1)));
        uint256 claimable = (w >> 128) + poolWei;
        w = (w & ((uint256(1) << 128) - 1)) | (claimable << 128);
        vm.store(address(game), bytes32(SLOT_POOLS_1), bytes32(w));
    }

    /// @dev Expired deity boons in every category a deity can issue (the deity draw skips the decimator
    ///      and deity-pass families): coinflip, lootbox, purchase and whale in slot0; lazy pass and the
    ///      craps, ETH, FLIP and WWXRP lanes in slot1. A recipient takes one deity boon a day, so the
    ///      nine sit on nine earlier days. None touches any other state of the winner.
    function _seedExpiredDeityBoons(address player) internal {
        uint256 d0 = today - 1;
        uint256 d1 = today - 2;
        uint256 d2 = today - 3;
        uint256 d3 = today - 4;
        uint256 d4 = today - 5;
        uint256 s0 = d0 | (d0 << 24) | (uint256(1) << 48) // coinflip: day, deity day, tier
            | (d1 << 56) | (d1 << 80) | (uint256(1) << 104) // lootbox
            | (d2 << 112) | (d2 << 136) | (uint256(1) << 160) // purchase
            | (d3 << 200) | (d3 << 224) | (uint256(1) << 248); // whale
        uint256 s1 = (d4 << 128) | (d4 << 152) | (uint256(1) << 176) // lazy pass
            | _deityLane(today - 6) // craps lane
            | (_deityLane(today - 7) << 184) // ETH lane
            | (_deityLane(today - 8) << 208) // FLIP lane
            | (_deityLane(today - 9) << 232); // WWXRP lane
        bytes32 base = keccak256(abi.encode(player, SLOT_BOON_PACKED));
        vm.store(address(game), base, bytes32(s0));
        vm.store(address(game), bytes32(uint256(base) + 1), bytes32(s1));
        (uint256 r0, uint256 r1) = game.boonPacked(player);
        require(r0 == s0 && r1 == s1, "boonPacked slot");
    }

    /// @dev A tier-1 deity lane stamped `day` (tier | deity bit | day << 3).
    function _deityLane(uint256 day) internal pure returns (uint256) {
        return 1 | 0x4 | ((day & 0x1FFFFF) << 3);
    }

    // =====================================================================
    // Rows
    // =====================================================================

    function _row(
        uint8 size,
        uint8 path,
        uint8 pay,
        uint8 boon,
        int256 offset,
        bool sweep,
        uint8 history,
        uint256 count,
        string memory label
    ) internal pure returns (Row memory) {
        return Row(size, path, pay, boon, offset, sweep, history, count, label);
    }

    /// @dev The branch groups, `count` fresh winners each, consecutive in one winning list. Group 0 is the
    ///      pilot, settled unmeasured so every group resumes the walk. Group 10 is one winner of each
    ///      branch (`_mixSpecs`), led by the first append at the open level while its write queue is empty
    ///      and the first seat reserved for tomorrow: what it costs beyond its members' marginals is what
    ///      a mixed call pays once.
    function _rows() internal pure returns (Row[] memory r) {
        r = new Row[](21);
        r[0] = _row(NO_WHALE, PATH_FLAT_FLIP, 0, BOON_ANY, OFFSET_ANY, false, PLAIN, 1, "pilot");
        r[1] = _row(DUST, PATH_ANY, 0, BOON_ANY, OFFSET_ANY, false, PLAIN, 4, "dust: half-passes, no box");
        r[2] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "FLIP spins, no payout");
        r[3] = _row(WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "whale: FLIP spins, no payout");
        r[4] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_NONE, OFFSET_ANY, true, PLAIN, 4, "sweep, no boon");
        r[5] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_WHALE_PASS, OFFSET_ANY, true, PLAIN, 3, "sweep + whale pass");
        r[6] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_DEITY_PASS, OFFSET_ANY, false, PLAIN, 4, "deity pass (slot1 first write)");
        r[7] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_QUEST_SHIELD, OFFSET_ANY, true, PLAIN, 4, "sweep + quest shield");
        r[8] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_COINFLIP, OFFSET_ANY, false, PLAIN, 4, "coinflip (slot0 first write)");
        r[9] = _row(NO_WHALE, PATH_WWXRP_SPIN, PAYS_NOTHING, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "WWXRP spin, no payout");
        r[10] = _row(NO_WHALE, PATH_ANY, 0, BOON_ANY, OFFSET_ANY, false, PLAIN, 15, "mixed: one of each branch");
        r[11] = _row(NO_WHALE, PATH_TICKETS, 0, BOON_NONE, OFFSET_NEW, false, PLAIN, 6, "tickets far levels, new words");
        r[12] = _row(NO_WHALE, PATH_PASSES, 0, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "passes (first seat, then later)");
        r[13] = _row(NO_WHALE, PATH_DGNRS, 0, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "DGNRS");
        r[14] = _row(NO_WHALE, PATH_WWXRP_SPIN, PAYS, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "WWXRP spin, paid");
        r[15] = _row(NO_WHALE, PATH_FLAT_FLIP, 0, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "flat FLIP");
        r[16] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS, BOON_NONE, OFFSET_ANY, false, PLAIN, 4, "FLIP spins, paid");
        r[17] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_ACTIVITY, OFFSET_ANY, true, RICH_AFK, 4, "sweep + afking activity");
        r[18] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_ACTIVITY, OFFSET_ANY, true, RICH, 4, "sweep + activity");
        r[19] = _row(WHALE, PATH_TICKETS, 0, BOON_ACTIVITY, OFFSET_NEW, true, RICH_AFK, 4, "whale: tickets new words + sweep + afking activity");
        // Additivity check: a priced lane on top of the costliest boon the base allows for.
        r[20] = _row(NO_WHALE, PATH_TICKETS, 0, BOON_WHALE_PASS, OFFSET_NEW, true, PLAIN, 3, "tickets new words + sweep + whale pass");
    }

    uint256 internal constant MIX = 10;

    /// @dev The mixed group's members, and the group whose in-batch marginal each one's branch carries.
    function _mixSpecs() internal pure returns (Row[] memory r, uint256[] memory branchGroup) {
        r = new Row[](15);
        branchGroup = new uint256[](15);
        r[0] = _row(NO_WHALE, PATH_TICKETS, 0, BOON_NONE, 0, false, PLAIN, 1, "tickets open level, empty queue");
        branchGroup[0] = 11;
        r[1] = _row(NO_WHALE, PATH_PASSES, 0, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "passes, first seat");
        branchGroup[1] = 12;
        r[2] = _row(NO_WHALE, PATH_DGNRS, 0, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "DGNRS");
        branchGroup[2] = 13;
        r[3] = _row(NO_WHALE, PATH_WWXRP_SPIN, PAYS, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "WWXRP paid");
        branchGroup[3] = 14;
        r[4] = _row(NO_WHALE, PATH_FLAT_FLIP, 0, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "flat FLIP");
        branchGroup[4] = 15;
        r[5] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "FLIP spins paid");
        branchGroup[5] = 16;
        r[6] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_QUEST_SHIELD, OFFSET_ANY, true, PLAIN, 1, "quest shield");
        branchGroup[6] = 7;
        r[7] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_ACTIVITY, OFFSET_ANY, true, RICH_AFK, 1, "afking activity");
        branchGroup[7] = 17;
        r[8] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_DEITY_PASS, OFFSET_ANY, false, PLAIN, 1, "deity pass");
        branchGroup[8] = 6;
        r[9] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_COINFLIP, OFFSET_ANY, false, PLAIN, 1, "coinflip");
        branchGroup[9] = 8;
        r[10] = _row(NO_WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_WHALE_PASS, OFFSET_ANY, true, PLAIN, 1, "whale pass");
        branchGroup[10] = 5;
        r[11] = _row(WHALE, PATH_FLIP_SPINS, PAYS_NOTHING, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "whale");
        branchGroup[11] = 3;
        r[12] = _row(DUST, PATH_ANY, 0, BOON_ANY, OFFSET_ANY, false, PLAIN, 1, "dust");
        branchGroup[12] = 1;
        r[13] = _row(NO_WHALE, PATH_WWXRP_SPIN, PAYS_NOTHING, BOON_NONE, OFFSET_ANY, false, PLAIN, 1, "WWXRP no payout");
        branchGroup[13] = 9;
        r[14] = _row(NO_WHALE, PATH_TICKETS, 0, BOON_NONE, OFFSET_NEW, false, PLAIN, 1, "tickets new word");
        branchGroup[14] = 11;
    }

    /// @dev The spec of the i-th winner in the list.
    function _specOf(uint256 i) internal view returns (Row memory) {
        if (rowGroup[i] != MIX) return _rows()[rowGroup[i]];
        (Row[] memory mix, ) = _mixSpecs();
        return mix[i - groupStart[MIX]];
    }

    function _grindRows() internal {
        Row[] memory rows = _rows();
        (Row[] memory mix, ) = _mixSpecs();
        rowUsed[0] = true; // the open level; only the mixed group's lead takes it
        for (uint256 i; i < rows.length; ++i) {
            groupStart.push(rowWinners.length);
            for (uint256 j; j < rows[i].count; ++j) {
                Row memory r = i == MIX ? mix[j] : rows[i];
                (address p, ) = _grind(r.path, r.pay, r.boon, r.offset, rowUsed);
                rowWinners.push(p);
                rowGroup.push(i);
            }
        }
    }

    /// @dev The full calls. Each opens with an open-level ticket settle and a first-seat pass settle, then
    ///      takes ticket settles on distinct far levels at word boundaries: whale-sized, swept winners
    ///      paying an afking activity award after the longest re-sync (and a one-settle twin), and
    ///      no-whale swept winners drawing the deity-pass boon.
    function _grindFullCalls() internal {
        fullUsed[0] = true;
        (address p, ) = _grind(PATH_TICKETS, 0, BOON_ACTIVITY, 0, fullUsed);
        fullWinners.push(p);
        (p, ) = _grind(PATH_PASSES, 0, BOON_ACTIVITY, OFFSET_ANY, fullUsed);
        fullWinners.push(p);
        for (uint256 i = 2; i < FULL_WINNERS; ++i) {
            (p, ) = _grind(PATH_TICKETS, 0, BOON_ACTIVITY, OFFSET_NEW, fullUsed);
            fullWinners.push(p);
        }
        (p, ) = _grind(PATH_TICKETS, 0, BOON_ACTIVITY, 0, oneUsed);
        oneWinner.push(p);

        laneUsed[0] = true;
        (p, ) = _grind(PATH_TICKETS, 0, BOON_DEITY_PASS, 0, laneUsed);
        laneWinners.push(p);
        (p, ) = _grind(PATH_PASSES, 0, BOON_DEITY_PASS, OFFSET_ANY, laneUsed);
        laneWinners.push(p);
        for (uint256 i = 2; i < LANE_WINNERS; ++i) {
            // Every far level once, on a new word; then later seats.
            (p, ) = i < TARGET_OFFSETS
                ? _grind(PATH_TICKETS, 0, BOON_DEITY_PASS, OFFSET_NEW, laneUsed)
                : _grind(PATH_PASSES, 0, BOON_DEITY_PASS, OFFSET_ANY, laneUsed);
            laneWinners.push(p);
        }
    }

    // =====================================================================
    // Branch prediction from the committed box seed
    // =====================================================================

    /// @dev keccak256(abi.encode(a, b)) in scratch space: the grind hashes millions of candidates, and an
    ///      allocating encode per candidate would exhaust memory.
    function _h2(uint256 a, uint256 b) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            r := keccak256(0x00, 0x40)
        }
    }

    /// @dev DecimatorModule._decSubbucketFor: keccak256(abi.encodePacked(player, lvl, bucket)) % bucket.
    function _subOf(address player) internal pure returns (uint8 sub) {
        uint256 word = (uint256(uint160(player)) << 96) | (uint256(LVL) << 72) | (uint256(DENOM) << 64);
        uint256 h;
        assembly ("memory-safe") {
            mstore(0x00, word)
            h := keccak256(0x00, 24)
        }
        sub = uint8(h % DENOM);
    }

    function _candidate(uint256 n) internal pure returns (address) {
        return address(uint160(_h2(uint256(keccak256("dec-wc")), n)));
    }

    function _inWinningList(uint256 i) internal view returns (address p) {
        for (uint256 n; ; ++n) {
            p = address(uint160(_h2(_h2(uint256(keccak256("dec-wc-typical")), i), n)));
            if (_subOf(p) == winSub) return p;
        }
    }

    /// @dev resolveLootboxDirect's seed: hash2(keccak(round word, tag, lvl), player).
    function _boxSeed(address player) internal view returns (uint256) {
        return _h2(boxWord, uint256(uint160(player)));
    }

    function _path(uint256 seed) internal pure returns (uint8) {
        uint256 roll = uint16(seed >> 40) % 20;
        if (roll < 8 || roll == 19) return PATH_TICKETS;
        if (roll < 11) return PATH_DGNRS;
        if (roll < 14) return PATH_WWXRP_SPIN;
        if (roll == 14) return PATH_FLAT_FLIP;
        if (roll < 17) return PATH_PASSES;
        return PATH_FLIP_SPINS;
    }

    /// @dev _rollTargetLevel's offset above level + 1.
    function _targetOffset(uint256 seed) internal pure returns (uint256) {
        if (uint16(seed) % 100 < 20) return uint16(seed >> 24) % 46 + 5;
        return uint8(seed >> 16) % 5;
    }

    function _boonKind(uint256 seed) internal view returns (uint8) {
        uint256 roll = uint32(_h2(seed, 0) >> 120) % 1_000_000;
        if (roll >= boonChance) return BOON_NONE;
        uint256 r = (roll * 2_856) / boonChance;
        if (r < 248) return BOON_COINFLIP;
        if (r >= 1_072 && r < 1_112) return BOON_DEITY_PASS;
        if (r >= 1_112 && r < 1_246) return BOON_ACTIVITY;
        if (r >= 1_246 && r < 1_446) return BOON_QUEST_SHIELD;
        if (r >= 1_446 && r < 1_448) return BOON_WHALE_PASS;
        return BOON_OTHER;
    }

    /// @dev Storage._lootboxEvMultiplierFromScore.
    function _evBps(uint256 score) internal pure returns (uint256) {
        if (score <= 60) return 9_000 + (score * 1_000) / 60;
        if (score >= 30_000) return 14_500;
        if (score <= 400) return 10_000 + ((score - 60) * 3_950) / 340;
        if (score <= 500) return 13_950 + ((score - 400) * 440) / 100;
        return 14_390 + ((score - 500) * 110) / 29_500;
    }

    /// @dev The boon draw's chance for a fresh-EV-cap winner's box in DENOM: the EV-scaled box's boon budget
    ///      (10%, capped at 1 ETH) over half the table's average max value (BoonModule._boonAvgMaxValue).
    function _boonTotalChance(uint256 boxAmount) internal view returns (uint256 chance) {
        uint256 scaled = (boxAmount * _evBps(ActivityCurveLib.minScoreForBucket(DENOM))) / 10_000;
        uint256 budget = (scaled * 1_000) / 10_000;
        if (budget > 1 ether) budget = 1 ether;
        uint256 lazy;
        for (uint24 i; i < 10; ++i) {
            lazy += PriceLookupLib.priceForLevel(curLevel + 1 + i);
        }
        uint256 avgMax = (1_568 ether + 4_182 * PriceLookupLib.priceForLevel(curLevel - 1) + 6 * lazy) / 2_856;
        chance = (budget * 1_000_000) / ((avgMax * 5_000) / 10_000);
        if (chance > 1_000_000) chance = 1_000_000;
    }

    /// @dev Whether the box's spin pays, screened through the Degenerette code etched over the Game.
    function _spinPays(address p, uint256 seed, uint8 path) internal returns (bool) {
        IDegenerusGameDegeneretteModule m = IDegenerusGameDegeneretteModule(address(game));
        if (path == PATH_WWXRP_SPIN) {
            return m.resolveWwxrpSpinFromBox(
                p, 1_000 ether, SCORE, uint256(keccak256(abi.encode(seed, BOX_WWXRP_SPIN_TAG))), 32
            ) != 0;
        }
        return m.resolveFlipSpinsFromBox(
            p, 100_000 ether, SCORE, uint256(keccak256(abi.encode(seed, BOX_FLIP_SPIN_TAG))), 32
        ) != 0;
    }

    /// @dev Next candidate that lands in the winning DENOM list and whose box rolls `path` (with the spin
    ///      outcome `pay`), draws `boon`, and (for tickets) targets an offset allowed by `offsetMode`. A pass
    ///      roll is taken only on the low FLIP band, whose budget always buys several normal passes, so the
    ///      table both reserves a day and banks the rest.
    function _grind(uint8 path, uint8 pay, uint8 boon, int256 offsetMode, bool[51] storage used)
        internal
        returns (address p, uint256 offset)
    {
        for (uint256 n = _cursor; n < _cursor + MAX_GRIND; ++n) {
            p = _candidate(n);
            if (_subOf(p) != winSub) continue;
            uint256 seed = _boxSeed(p);
            if (path != PATH_ANY && _path(seed) != path) continue;
            if (boon != BOON_ANY && _boonKind(seed) != boon) continue;
            if (path == PATH_PASSES && uint16(seed >> 80) % 20 >= 16) continue;
            if (path == PATH_TICKETS) {
                offset = _targetOffset(seed);
                if (offsetMode >= 0) {
                    if (offset != uint256(offsetMode)) continue;
                } else if (offsetMode == OFFSET_NEW && used[offset]) {
                    continue;
                }
            }
            if (pay != 0 && _spinPays(p, seed, path) != (pay == PAYS)) continue;
            if (path == PATH_TICKETS && offsetMode == OFFSET_NEW) used[offset] = true;
            _cursor = n + 1;
            return (p, offset);
        }
        revert("grind exhausted");
    }

    // =====================================================================
    // Measurement
    // =====================================================================

    /// @dev Every protocol account and all of its storage cold, as at the start of a transaction.
    function _coolAll() internal {
        address[31] memory a = [
            ContractAddresses.GAME,
            ContractAddresses.GAME_MINT_MODULE,
            ContractAddresses.GAME_ADVANCE_MODULE,
            ContractAddresses.GAME_WHALE_MODULE,
            ContractAddresses.GAME_JACKPOT_MODULE,
            ContractAddresses.GAME_DECIMATOR_MODULE,
            ContractAddresses.GAME_GAMEOVER_MODULE,
            ContractAddresses.GAME_LOOTBOX_MODULE,
            ContractAddresses.GAME_BOON_MODULE,
            ContractAddresses.GAME_DEGENERETTE_MODULE,
            ContractAddresses.GAME_BINGO_MODULE,
            ContractAddresses.GAME_AFKING_MODULE,
            ContractAddresses.GAME_FOILPACK_MODULE,
            ContractAddresses.COIN,
            ContractAddresses.COINFLIP,
            ContractAddresses.VAULT,
            ContractAddresses.AFFILIATE,
            ContractAddresses.JACKPOTS,
            ContractAddresses.QUESTS,
            ContractAddresses.SDGNRS,
            ContractAddresses.DGNRS,
            ContractAddresses.DEITY_PASS,
            ContractAddresses.WWXRP,
            ContractAddresses.GNRUS,
            ContractAddresses.AFKING_SUB_TOKEN,
            ContractAddresses.PARIMUTUEL,
            ContractAddresses.RECORD_BOUNTY,
            ContractAddresses.CRAPS,
            ContractAddresses.CRAPS_ENGINE,
            ContractAddresses.JACKPOT_BATTLE,
            ContractAddresses.STETH_TOKEN
        ];
        for (uint256 i; i < a.length; ++i) {
            vm.cool(a[i]);
        }
    }

    /// @dev What `p`'s settle did, from its events: the deferral and the box from DecimatorClaimed's
    ///      lootbox portion, and one flag per paid lane (the ticket flush, the DGNRS batch, the FLIP credit,
    ///      the WWXRP mint, the pass delivery) plus the activity awards and their full re-syncs.
    function _comp(Vm.Log[] memory logs, address p, bool swept) internal pure returns (Comp memory c) {
        bytes32 who = bytes32(uint256(uint160(p)));
        bool claimed;
        uint256 rewards;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length < 2) continue;
            bytes32 t0 = l.topics[0];
            if (t0 == TRANSFER_SIG) {
                if (l.emitter == ContractAddresses.WWXRP && l.topics[1] == bytes32(0) && l.topics[2] == who) {
                    c.wwxrp = true;
                }
                continue;
            }
            if (l.topics[1] != who) continue;
            if (t0 == DEC_CLAIMED_SIG) {
                (, , uint256 lootbox) = abi.decode(l.data, (uint256, uint256, uint256));
                claimed = true;
                if (lootbox > 5 ether) {
                    c.whale = true;
                    c.box = lootbox % 2.25 ether >= 0.01 ether;
                } else {
                    c.box = lootbox != 0;
                }
            } else if (t0 == ENTRIES_QUEUED_SIG && l.emitter == ContractAddresses.GAME) {
                ++c.lanes;
            } else if (t0 == DGNRS_BATCH_SIG) {
                c.dgnrs = true;
            } else if (t0 == FLIP_STAKE_SIG && l.emitter == ContractAddresses.COINFLIP) {
                c.flip = true;
            } else if (t0 == PASSES_SIG) {
                c.pass = true;
            } else if (t0 == BOON_CONSUMED_SIG) {
                (uint8 kind,) = abi.decode(l.data, (uint8, uint16));
                if (kind == 5) ++c.activity;
            } else if (t0 == BOON_REWARD_SIG && l.emitter == ContractAddresses.GAME) {
                ++rewards;
            } else if ((t0 == WHALE_PASS_BOON_SIG || t0 == BOON_DISCARDED_SIG) && l.emitter == ContractAddresses.GAME) {
                ++c.boons;
            } else if (t0 == BOX_SPIN_SIG && l.emitter == ContractAddresses.GAME) {
                ++c.spins;
            } else if (t0 == SHIELD_USED_SIG && l.emitter == ContractAddresses.QUESTS) {
                (uint16 used,,) = abi.decode(l.data, (uint16, uint16, uint24));
                if (used == 255) ++c.fullResync;
            }
        }
        require(claimed, "not settled");
        // Every delivered boon logs one LootBoxReward except the whale pass (its own event); the
        // activity award logs one too.
        c.boons += rewards - c.activity;
        c.swept = swept && c.box;
    }

    /// @dev The settle's walk units under `k` (the lead units are the caller's).
    function _units(Comp memory c, Prices memory k) internal pure returns (uint256 u) {
        u = k.settle + (c.whale ? k.whale : 0);
        if (!c.box) return u;
        u += k.base + c.lanes * k.lane + c.activity * k.activity + c.boons * k.boon + c.spins * k.spin;
        if (c.swept) u += k.sweep;
        if (c.dgnrs) u += k.dgnrs;
        if (c.flip) u += k.flip;
        if (c.wwxrp) u += k.wwxrp;
        if (c.pass) u += k.pass;
    }

    function _mirrored() internal pure returns (Prices memory) {
        return Prices(
            K_CALL, K_SETTLE, K_WHALE, K_BASE, K_SPIN, K_BOON, K_SWEEP, K_LANE, K_DGNRS, K_FLIP, K_WWXRP, K_PASS, K_ACTIVITY
        );
    }

    function _sub0(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _checkSpec(Row memory r, Comp memory c) internal pure {
        require(c.whale == (r.size != NO_WHALE), "spec: deferral");
        require(c.box == (r.size != DUST), "spec: box");
        if (!c.box) return;
        require(c.lanes == (r.path == PATH_TICKETS ? 1 : 0), "spec: tickets");
        require(c.dgnrs == (r.path == PATH_DGNRS), "spec: DGNRS");
        require(c.flip == (r.path == PATH_FLAT_FLIP || (r.path == PATH_FLIP_SPINS && r.pay == PAYS)), "spec: FLIP");
        require(c.wwxrp == (r.path == PATH_WWXRP_SPIN && r.pay == PAYS), "spec: WWXRP");
        require(c.pass == (r.path == PATH_PASSES), "spec: passes");
        require(c.activity == (r.boon == BOON_ACTIVITY ? 1 : 0), "spec: activity");
        require(c.fullResync == c.activity, "spec: longest re-sync");
        require(c.spins == (r.path == PATH_WWXRP_SPIN || r.path == PATH_FLIP_SPINS ? 1 : 0), "spec: spin");
        if (r.boon != BOON_ANY) {
            require(c.boons == (r.boon != BOON_NONE && r.boon != BOON_ACTIVITY ? 1 : 0), "spec: boon");
        }
    }

    // =====================================================================
    // The calibration rows
    // =====================================================================

    /// @dev The walk units a settle of spec `r` is charged under `k` (without the call price).
    function _predicted(Row memory r, Prices memory k) internal pure returns (uint256 u) {
        u = k.settle + (r.size == WHALE || r.size == DUST ? k.whale : 0);
        if (r.size == DUST) return u;
        u += k.base;
        if (r.path == PATH_TICKETS) u += k.lane;
        if (r.path == PATH_DGNRS) u += k.dgnrs;
        if (r.path == PATH_FLAT_FLIP || (r.path == PATH_FLIP_SPINS && r.pay == PAYS)) u += k.flip;
        if (r.path == PATH_WWXRP_SPIN && r.pay == PAYS) u += k.wwxrp;
        if (r.path == PATH_PASSES) u += k.pass;
        if (r.boon == BOON_ACTIVITY) u += k.activity;
        if (r.boon != BOON_NONE && r.boon != BOON_ACTIVITY && r.boon != BOON_ANY) u += k.boon;
        if (r.path == PATH_WWXRP_SPIN || r.path == PATH_FLIP_SPINS) u += k.spin;
        if (r.sweep) u += k.sweep;
    }

    /// @dev One cold harness call from the cursor with `budget` units: its gas, settles and charge.
    function _walkCold(uint256 budget) internal returns (uint256 gasUsed, uint256 settled, uint256 charged) {
        _coolAll();
        (settled, charged, ) = DecimatorWalkHarness(payable(address(game))).settleDec(budget);
        gasUsed = vm.lastCallGas().gasTotalUsed;
    }

    /// @notice Each branch group measured inside a batch: a cold call settling the group's first winner,
    ///         and, from the same state, a cold call settling all of it. The difference over the extra
    ///         settles is the branch's in-batch marginal; the one-settle call less a marginal is what a
    ///         call pays once. Every multi-settle call must fit the units the walk charged for it (the call
    ///         price included once), the walk must charge the mirrored prices, and the prices the
    ///         groups imply are derived.
    function test_calibration_InBatchBranches() public {
        Row[] memory rows = _rows();
        Prices memory k = _mirrored();
        uint256 pool;
        for (uint256 i; i < rowWinners.length; ++i) {
            Row memory r = _specOf(i);
            pool += _burn(rowWinners[i], r.size);
            if (r.sweep) _seedExpiredDeityBoons(rowWinners[i]);
        }
        _draw(pool);

        bytes memory original = address(game).code;
        vm.etch(address(game), type(DecimatorWalkHarness).runtimeCode);
        DecimatorWalkHarness(payable(address(game))).settleDec(FIRST_LEAD_UNITS + 1);

        uint256 n = rows.length;
        uint256[] memory one = new uint256[](n);
        uint256[] memory batch = new uint256[](n);
        uint256[] memory marginal = new uint256[](n);
        for (uint256 g = 1; g < n; ++g) {
            Row memory r = rows[g];
            if (g == MIX) {
                assertEq(_queueLengthAt(0), 0, "the mixed group appends to an empty queue");
                assertEq(_dayTickets(today + 1), 0, "the mixed group takes the first seat");
            }
            uint256 snap = vm.snapshotState();
            (uint256 gasOne, uint256 settledOne, ) = _walkCold(RESUME_LEAD_UNITS + 1);
            assertEq(settledOne, 1, "one settle");
            vm.revertToState(snap);

            uint256 budget = RESUME_LEAD_UNITS + k.call + 1;
            for (uint256 j; j + 1 < r.count; ++j) {
                budget += _predicted(_specOf(groupStart[g] + j), k);
            }
            vm.recordLogs();
            (uint256 gasAll, uint256 settled, uint256 charged) = _walkCold(budget);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(settled, r.count, "the group settles in one call");
            uint256 model = RESUME_LEAD_UNITS + k.call;
            for (uint256 j; j < r.count; ++j) {
                Comp memory c = _comp(logs, rowWinners[groupStart[g] + j], _specOf(groupStart[g] + j).sweep);
                _checkSpec(_specOf(groupStart[g] + j), c);
                model += _units(c, k);
            }
            assertEq(charged, model, "the walk charges the mirrored prices");
            assertLe(gasAll, charged * UNIT_GAS, string.concat("the batch fits its charge: ", r.label));
            one[g] = gasOne;
            batch[g] = gasAll;
            if (r.count > 1) marginal[g] = (gasAll - gasOne) / (r.count - 1);
        }
        vm.etch(address(game), original);
        (uint256 b0, uint256 b1) = game.boonPacked(rowWinners[groupStart[19]]);
        assertEq(b0 | b1, 0, "expired deity boons swept");

        _logPrices("mirrored prices (K_*)", k);
        _logPrices("prices the groups imply", _derive(one, batch, marginal));
        console2.log("group: in-batch marginal | units per settle under K_* | marginal / units x 4700 (bps) | once per call");
        for (uint256 g = 1; g < n; ++g) {
            uint256 u = _predicted(rows[g], k);
            console2.log(string.concat(vm.toString(g), " ", rows[g].label));
            if (g == MIX) {
                console2.log("    mixed call, once-per-call cost", batch[g] - _mixMarginals(marginal));
            } else if (rows[g].count > 1) {
                console2.log("    ", marginal[g], u, (marginal[g] * 10_000) / (u * UNIT_GAS));
                console2.log("    ", one[g] - marginal[g]);
            } else {
                console2.log("    one-settle call", one[g], u);
            }
        }
    }

    /// @dev Units for `gasUsed`, rounded up.
    function _units(uint256 gasUsed) internal pure returns (uint256) {
        return (gasUsed + UNIT_GAS - 1) / UNIT_GAS;
    }

    /// @dev The prices the groups imply, each part attributed in gas from in-batch deltas, then rounded up:
    ///        - the deferral: the whale group's marginal less its no-whale twin's;
    ///        - the frame: the dust marginal less the deferral;
    ///        - the box base: the cheapest box (one unpaid WWXRP spin, no boon, no sweep);
    ///        - the spin: the dearest spin roll (three FLIP spins) over the base;
    ///        - the sweep and the boon: their groups over the same box without them;
    ///        - each lane: its group's marginal less the base box (less the spin, boon and sweep the
    ///          group also carries);
    ///        - the activity award: its groups over the same box without a boon, plus the long
    ///          re-sync's warm word reads;
    ///        - the call: the mixed call less its members' in-batch marginals (every first touch, the
    ///          empty open-level queue and tomorrow's first seat), plus the empty-queue premium for the
    ///          second level that can hold one, and the long re-sync's cold word reads; less the lead units.
    function _derive(uint256[] memory one, uint256[] memory batch, uint256[] memory m)
        internal
        pure
        returns (Prices memory d)
    {
        uint256 whaleGas = _sub0(m[3], m[2]);
        uint256 settleGas = _sub0(m[1], whaleGas);
        // Every box rolls once; the cheapest roll (one unpaid WWXRP spin) is the base, and a roll's
        // own part is what it adds over that.
        uint256 baseGas = _sub0(m[9], settleGas);
        uint256 spinGas = _sub0(m[2], m[9]);
        uint256 sweepGas = _sub0(m[4], m[2]);
        uint256 boonGas = _max(_max(_sub0(m[5], m[4]), _sub0(m[7], m[4])), _max(_sub0(m[6], m[2]), _sub0(m[8], m[2])));
        uint256 laneGas = _max(_sub0(m[11], m[9]), _sub0(m[20], m[9] + sweepGas + boonGas));
        uint256 passGas = _sub0(m[12], m[9]);
        uint256 dgnrsGas = _sub0(m[13], m[9]);
        uint256 wwxrpGas = _sub0(m[14], m[9] + spinGas);
        uint256 flipGas = _max(_sub0(m[15], m[9]), _sub0(m[16], m[2]));
        uint256 actGas = _max(_sub0(m[17], m[4]), _sub0(m[18], m[4]));
        actGas = _max(actGas, _sub0(m[19], settleGas + whaleGas + baseGas + laneGas + sweepGas));
        actGas += LONG_RESYNC_WORDS * RESYNC_WORD_WARM_GAS;

        uint256 callGas = batch[MIX] - _mixMarginals(m);
        callGas += (EMPTY_WRITE_QUEUES - 1) * _sub0(one[MIX], one[11]);
        callGas += LONG_RESYNC_WORDS * RESYNC_WORD_COLD_GAS;

        d.call = _sub0(_units(callGas), RESUME_LEAD_UNITS);
        d.settle = _units(settleGas);
        d.whale = _units(whaleGas);
        d.base = _units(baseGas);
        d.spin = _units(spinGas);
        d.boon = _units(boonGas);
        d.sweep = _units(sweepGas);
        d.lane = _units(laneGas);
        d.pass = _units(passGas);
        d.dgnrs = _units(dgnrsGas);
        d.wwxrp = _units(wwxrpGas);
        d.flip = _units(flipGas);
        d.activity = _units(actGas);
    }

    /// @dev The sum of the mixed group's members' in-batch marginals.
    function _mixMarginals(uint256[] memory m) internal pure returns (uint256 sum) {
        (, uint256[] memory branchGroup) = _mixSpecs();
        for (uint256 j; j < branchGroup.length; ++j) {
            sum += m[branchGroup[j]];
        }
    }

    function _laneCount(Comp memory c) internal pure returns (uint256 k) {
        k = c.lanes;
        if (c.dgnrs) ++k;
        if (c.flip) ++k;
        if (c.wwxrp) ++k;
        if (c.pass) ++k;
    }

    function _logPrices(string memory title, Prices memory k) internal pure {
        console2.log(title);
        console2.log("  DEC_CALL_UNITS    ", k.call);
        console2.log("  DEC_SETTLE_UNITS  ", k.settle);
        console2.log("  DEC_WHALE_UNITS   ", k.whale);
        console2.log("  BOX_BASE_UNITS    ", k.base);
        console2.log("  BOX_SPIN_UNITS    ", k.spin);
        console2.log("  BOX_BOON_UNITS    ", k.boon);
        console2.log("  BOX_SWEEP_UNITS   ", k.sweep);
        console2.log("  BOX_LANE_UNITS    ", k.lane);
        console2.log("  BOX_DGNRS_UNITS   ", k.dgnrs);
        console2.log("  BOX_FLIP_UNITS    ", k.flip);
        console2.log("  BOX_WWXRP_UNITS   ", k.wwxrp);
        console2.log("  BOX_PASS_UNITS    ", k.pass);
        console2.log("  BOX_ACTIVITY_UNITS", k.activity);
    }

    // =====================================================================
    // Full mineFlip calls
    // =====================================================================

    /// @dev Burn `winners` (alone in the round's DENOM winning list, in order), sweep-seed them if asked,
    ///      and draw.
    function _install(address[] storage winners, uint8 size, bool sweep) internal {
        uint256 pool;
        for (uint256 i; i < winners.length; ++i) {
            pool += _burn(winners[i], size);
            if (sweep) _seedExpiredDeityBoons(winners[i]);
        }
        _draw(pool);
    }

    /// @dev Every winner's settle outcome, from one unbounded harness walk (state reverted after).
    function _outcomes(address[] storage winners, bool swept) internal returns (Comp[] memory c) {
        uint256 snap = vm.snapshotState();
        vm.etch(address(game), type(DecimatorWalkHarness).runtimeCode);
        vm.recordLogs();
        DecimatorWalkHarness(payable(address(game))).settleDec(type(uint64).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        c = new Comp[](winners.length);
        for (uint256 i; i < winners.length; ++i) {
            c[i] = _comp(logs, winners[i], swept);
        }
        vm.revertToState(snap);
    }

    /// @dev Settles one mineFlip call makes under `k`: each starts while the walk has budget left and is
    ///      charged after it runs.
    function _settlesPerCall(Comp[] memory c, Prices memory k) internal pure returns (uint256 settled, uint256 used) {
        used = FIRST_LEAD_UNITS;
        while (settled < c.length && used < DEC_WALK_BUDGET) {
            if (settled == 0) used += k.call;
            used += _units(c[settled], k);
            ++settled;
        }
    }

    /// @dev The largest charge one settle can take under `k`: the frame, the deferral, and a box with the
    ///      dearest roll (a ticket lane, over passes and the spin payouts), the dearest draw (an activity
    ///      award, over any other boon) and the sweep.
    function _maxSettleUnits(Prices memory k) internal pure returns (uint256) {
        uint256 roll = _max(_max(k.lane, k.pass), _max(k.spin + _max(k.flip, k.wwxrp), k.dgnrs));
        return k.settle + k.whale + k.base + roll + _max(k.activity, k.boon) + k.sweep;
    }

    function _mineCold() internal returns (uint256 gasUsed, uint256 settled) {
        _coolAll();
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        gasUsed = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == DEC_CLAIMED_SIG) ++settled;
        }
    }

    /// @notice The heaviest full call: whale-sized, swept winners, each paying a ticket level (an empty
    ///         open-level queue first, then a first seat, then far levels at word boundaries) and an
    ///         afking activity award after the longest re-sync.
    function test_calibration_FullMineFlipHeaviest() public {
        uint256 snap = vm.snapshotState();
        _install(oneWinner, WHALE, true);
        (uint256 gasOne, uint256 settledOne) = _mineCold();
        assertEq(settledOne, 1, "one-settle call");
        vm.revertToState(snap);

        _install(fullWinners, WHALE, true);
        Comp[] memory c = _outcomes(fullWinners, true);
        (uint256 expected, uint256 units) = _settlesPerCall(c, _mirrored());
        // The leg alone, from the same state and with the same budget: what mineFlip adds around it is
        // the router tail.
        snap = vm.snapshotState();
        vm.etch(address(game), type(DecimatorWalkHarness).runtimeCode);
        _coolAll();
        DecimatorWalkHarness(payable(address(game))).settleDec(DEC_WALK_BUDGET);
        uint256 gasLeg = vm.lastCallGas().gasTotalUsed;
        vm.revertToState(snap);
        (uint256 gasFull, uint256 settled) = _mineCold();
        uint256 tail = gasFull > gasLeg ? gasFull - gasLeg : 0;
        uint256 proven = (DEC_WALK_BUDGET + _maxSettleUnits(_mirrored())) * UNIT_GAS + tail + TX_INTRINSIC;
        console2.log("proven bound: largest settle charge, router tail", _maxSettleUnits(_mirrored()), tail);
        console2.log("proven bound: (budget + largest settle) x 4700 + tail + intrinsic", proven);
        assertLe(proven, REALISTIC_CEILING, "the proven bound stays within 10M");

        console2.log("heaviest: settles under K_*, units", expected, units);
        console2.log("heaviest: settles by the contract", settled);
        console2.log("heaviest: gas + intrinsic", gasFull + TX_INTRINSIC);
        console2.log("one-settle call: gas", gasOne);
        console2.log("per-settle marginal in the call", (gasFull - gasOne) / (settled - 1));
        console2.log("per-settle units under K_*: ticket, passes", _units(c[2], _mirrored()), _units(c[1], _mirrored()));

        assertEq(settled, expected, "the call settles what the mirrored prices allow");
        assertLe(gasFull + TX_INTRINSIC, REALISTIC_CEILING, "heaviest full call within 10M");
    }

    /// @notice The heaviest full call without activity awards: no-whale winners carrying swept boon slots
    ///         and a slot1 boon, each paying a ticket level (an empty open-level queue first, then a first
    ///         seat, then far levels at word boundaries), the branch closest to its charge.
    function test_calibration_FullMineFlipLanes() public {
        _install(laneWinners, NO_WHALE, true);
        Comp[] memory c = _outcomes(laneWinners, true);
        (uint256 expected, uint256 units) = _settlesPerCall(c, _mirrored());
        (uint256 gasUsed, uint256 settled) = _mineCold();
        console2.log("lanes, no award: settles under K_*, units", expected, units);
        console2.log("lanes, no award: settles by the contract", settled);
        console2.log("lanes, no award: gas + intrinsic", gasUsed + TX_INTRINSIC);
        assertEq(settled, expected, "the call settles what the mirrored prices allow");
        assertLe(gasUsed + TX_INTRINSIC, REALISTIC_CEILING, "lanes full call within 10M");
    }

    /// @notice A typical batch: 2 ETH wins (a 1 ETH box), plain winners, whatever their boxes roll.
    function test_calibration_FullMineFlipTypical() public {
        _install(typicalWinners, TYPICAL, false);
        Comp[] memory c = _outcomes(typicalWinners, false);
        (uint256 expected, uint256 units) = _settlesPerCall(c, _mirrored());
        (uint256 gasUsed, uint256 settled) = _mineCold();
        console2.log("typical 1 ETH boxes: settles under K_*, units", expected, units);
        console2.log("typical 1 ETH boxes: settles by the contract", settled);
        console2.log("typical 1 ETH boxes: gas + intrinsic", gasUsed + TX_INTRINSIC);
        assertEq(settled, expected, "the call settles what the mirrored prices allow");
        assertLe(gasUsed + TX_INTRINSIC, REALISTIC_CEILING, "typical full call within 10M");
        assertGe(gasUsed + TX_INTRINSIC, TYPICAL_FLOOR, "typical full call uses its budget");
    }
}
