// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {ProtocolBoonDrawSeeder} from "./helpers/ProtocolBoonDrawSeeder.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {DayOneSeeder, DayOneFixture} from "./JackpotDayOneWorstCase.t.sol";

/// @title PurchaseDailyWorstCase — the per-tx gas ceiling of the PURCHASE-PHASE daily advance.
/// @notice STAGE_PURCHASE_DAILY (6) pays the ETH and FLIP legs and prices the ticket leg in one
///         advanceGame tx; STAGE_PURCHASE_DAILY_TICKETS (15) pays that ticket leg from the next
///         advance on the same recorded word and seals the day. The three winner-capped legs:
///           - the daily ETH leg: fixed buckets [24,16,8,1] = 49 winners off 23% of the 1%
///             futurePrizePool drip (`payDailyJackpot(false)` -> `_processDailyEth`);
///           - the daily ticket leg: up to PURCHASE_PHASE_TICKET_MAX_WINNERS = 120 winners
///             (40 per non-solo quadrant) once the 50% ticket basis of the 75% ticket-leg
///             budget covers 120 whole tickets at priceForLevel(purchaseLevel)
///             (`_distributePoolBackedTickets` -> `_queueEntries`, a cold registry push + queue
///             push + owed write per fresh winner);
///           - the daily FLIP leg: DAILY_COIN_MAX_WINNERS = 50 near-future pulls over
///             [purchaseLevel+1, purchaseLevel+4] plus FAR_FUTURE_FLIP_SAMPLES = 8 far-future
///             pulls, credited through ONE coinflip.creditFlipBatch each
///             (`_payDailyCoinJackpot` -> `payDailyFlipJackpot`);
///         and, on the day the next-pool target is met at an x0 purchase level, the
///         last-purchase latch + coinflip.armBafDraw ride the same tx.
///         This suite measures that tx on the REAL advanceGame bytecode at every cap, with every
///         winner a distinct address holding no claimable / no queued entries / no flip stake
///         (cold SSTOREs), and asserts it under the EIP-7825 cap.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding happens in setUp() — a SEPARATE
///      transaction from the measured body — so the measured call starts on a cold EIP-2929 access
///      list, as a real keeper tx would (the JackpotDayOneWorstCase pattern). As there, the day's
///      word is pre-recorded (rngWordByDay[day] != 0), so the rngGate word-apply leg
///      (coinflip.processCoinflipPayouts + craps openBonusDay) is NOT in the measured figure.
///      Samplers draw WITH replacement; the suite counts distinct winners.
contract PurchaseDailySeeder is DegenerusGame, BucketSeed {
    struct Shape {
        uint24 lvl; // storage `level`; the daily pays purchaseLevel = lvl + 1
        uint256 word; // the day's recorded VRF word
        uint160 base; // disjoint address-space base for synthetic holders
        uint256 mainHolders; // distinct holders per main-board bucket at purchaseLevel (ETH + ticket legs)
        uint256 bonusHolders; // distinct holders per bonus-board bucket at purchaseLevel+1..+4 (FLIP leg)
        uint256 ffHolders; // distinct holders per far-future queue at purchaseLevel+5..+99 (FLIP far leg)
        uint128 nextPool; // nextPrizePool (> prevPool latches last-purchase + BAF arm at x0)
        uint128 futurePool; // futurePrizePool: the 1% drip sizes the ETH and ticket legs
        uint256 prevPool; // levelPrizePool[purchaseLevel-1]: sizes the FLIP budget and the latch target
    }

    function seedPurchaseDaily(Shape calldata s, uint8[4] calldata mainTraits, uint8[4] calldata bonusTraits)
        external
    {
        uint24 day = _simulatedDayIndex();
        uint24 pl = s.lvl + 1;

        // Purchase-phase day shape: day == dailyIdx + 1, the day's request locked with its word
        // already recorded (rngGate returns it; no request, no subscriber stage), read slot
        // drained, no carryover / coin-ticket leg pending, no golden ticket, no hero wagers.
        level = s.lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        compressedJackpotFlag = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        jackpotCounter = 0;
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = s.word;
        rngWordByDay[day] = s.word;
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
        levelPrizePool[s.lvl] = s.prevPool;
        currentPrizePool = uint128(100 ether);
        _setPrizePools(s.nextPool, s.futurePool);

        // The empty-FLIP split deliberately excludes protocol participation too:
        // real genesis passes now supply virtual buckets and far-future tickets.
        if (s.bonusHolders == 0) {
            deityBySymbol[VAULT_DEITY_SYMBOL] = address(0);
            deityBySymbol[SDGNRS_DEITY_SYMBOL] = address(0);
        }
        if (s.ffHolders == 0) {
            for (uint24 c = pl + 5; c <= pl + 99; ++c) {
                uint256[] storage emptyQueue = ticketQueue[_tqFarFutureKey(c)];
                assembly ("memory-safe") { sstore(emptyQueue.slot, 0) }
            }
        }

        // Keep registry position 0 out of every seeded level (a zero lane index understates gas).
        for (uint24 L = pl; L <= pl + 4; ++L) {
            if (lvlEntryOwner[L].length == 0) lvlEntryOwner[L].push(EntryOwner(address(1), 0));
        }

        for (uint8 q; q < 4; ++q) {
            if (s.mainHolders != 0) {
                _seedBucketDistinct(pl, mainTraits[q], s.mainHolders, s.base + uint160(q) * 0x100000);
            }
            if (s.bonusHolders != 0) {
                for (uint24 k; k < 4; ++k) {
                    _seedBucketDistinct(
                        pl + 1 + k,
                        bonusTraits[q],
                        s.bonusHolders,
                        s.base + 0x800000 + uint160(k) * 0x400000 + uint160(q) * 0x100000
                    );
                }
            }
        }

        if (s.ffHolders != 0) {
            for (uint24 c = pl + 5; c <= pl + 99; ++c) {
                uint256[] storage q = ticketQueue[_tqFarFutureKey(c)];
                uint160 b = s.base + 0x2000000 + uint160(c - pl - 5) * 0x1000;
                for (uint256 i; i < s.ffHolders; ++i) {
                    _tqAppend(_tqFarFutureKey(c), uint32(_registerEntryOwner(address(b + uint160(i + 1)), c) >> OWNER_IDX_SHIFT));
                }
            }
        }
    }

    /// @dev Un-record the day's word: the day is fresh and unlocked, so the next advance fires the
    ///      real VRF request and the one after applies the fulfilled word in the SAME tx as the stage.
    function unrecordWord() external {
        uint24 day = _simulatedDayIndex();
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = 0;
        rngWordByDay[day] = 0;
        vrfRequestId = 0;
        prizePoolFrozen = false;
    }
}

/// @dev The day-1 jackpot-phase seeder with the same un-record door.
contract DayOneUnrecordedSeeder is DayOneSeeder {
    function unrecordWord() external {
        uint24 day = _simulatedDayIndex();
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = 0;
        rngWordByDay[day] = 0;
        vrfRequestId = 0;
        prizePoolFrozen = false;
    }
}

/// @dev The rngGate word-apply leg, driven for real: book the craps table's 7-day action window (so
///      openBonusDay draws a high budget and posts stakes), settle Coinflip through day-1 (so the
///      measured sDGNRS settle walks exactly one day, the steady-state shape, not the day-400 jump),
///      fire the day's VRF request from the real advanceGame, and fulfil it on the mock coordinator.
///      The NEXT advanceGame then applies the word (_applyDailyRng, coinflip.processCoinflipPayouts,
///      quests.rollDailyQuest, craps openBonusDay, _finalizeLootboxRng) AND runs the stage in one tx.
abstract contract FreshWordLeg is DeployProtocol {
    uint8 internal constant STAGE_RNG_REQUESTED_ = 1;
    uint256 internal constant CRAPS_DAY_STAKED_SLOT = 10; // CrapsBattle `_dayStaked` (forge inspect)

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
}

/// @dev Shared measurement seam: warp, etch-seed-restore, drive the live advanceGame, classify winners.
abstract contract PurchaseDailyFixture is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this is a permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev The 10M soft design target the drains are sized to (USER dual bound).
    uint256 internal constant GAS_TARGET = 10_000_000;

    bytes32 internal constant ETH_WIN_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant FAR_WIN_SIG = keccak256("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
    bytes32 internal constant COMP_WIN_SIG = keccak256("JackpotCrapsCompWin(address,uint24,uint8,uint32,uint256)");
    bytes32 internal constant BAF_ARMED_SIG = keccak256("BafDrawArmed(uint24)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint16 internal constant PURCHASE_ETH_WINNERS = 49; // 24 + 16 + 8 + 1
    uint16 internal constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;
    uint16 internal constant DAILY_COIN_MAX_WINNERS = 50;
    uint8 internal constant FAR_FUTURE_FLIP_SAMPLES = 8;

    /// @dev level 109 -> purchaseLevel 110: an x0 (BAF) purchase level at the 0.04 ETH price tier,
    ///      so the target-met latch also arms the BAF draw in the measured tx.
    uint24 internal constant LVL = 109;
    uint160 internal constant BASE = uint160(0x1000000000);
    uint256 internal constant MAIN_HOLDERS = 5000; // per main bucket: ~60 draws each, ~0.4 expected repeats
    uint256 internal constant BONUS_HOLDERS = 200; // per (level, trait): ~3 draws each
    uint256 internal constant FF_HOLDERS = 8; // per far-future level: 8 lanes of one level's word
    /// @dev Sizing (price 0.04 ETH at 110/111, PRICE_COIN_UNIT 1000 FLIP):
    ///      - future 5000 ETH -> slice 50, ticket leg 37.5, basis 18.75 -> 468 whole tickets >= 120 cap;
    ///        ETH leg 11.5 ETH -> every 20%-share bucket (2.3 ETH) clears its unit*count rounding floor.
    ///      - prev 1000 ETH -> coinBudget 62,500 FLIP (< 4 day passes, so no comp mode): near 46,875
    ///        -> 468 units >= 50 pulls; far 15,625 -> 156 units >= 8 samples.
    ///      - next 1001 ETH > prev -> the last-purchase latch + BAF arm fire in the same tx.
    uint128 internal constant FUTURE_POOL = 5000 ether;
    uint256 internal constant PREV_POOL = 1000 ether;
    uint128 internal constant NEXT_POOL_LATCH = 1001 ether;
    uint128 internal constant NEXT_POOL_QUIET = 50 ether;
    /// @dev prev 12,000 ETH -> coinBudget 750,000 FLIP, near budget 562,500 -> 6 fundable comps (the
    ///      CRAPS_COMP_MAX_SLOTS ceiling; comps are sized off the 75% near budget), 425,700 FLIP
    ///      left over -> every remaining pull still funded.
    uint256 internal constant PREV_POOL_COMP = 12_000 ether;

    struct Tally {
        uint8 stage;
        uint256 ethWins;
        uint256 ethDistinct;
        uint256 ticketWins;
        uint256 ticketDistinct;
        uint256 flipWins;
        uint256 flipDistinct;
        uint256 farWins;
        uint256 farDistinct;
        uint256 compWins;
        bool bafArmed;
    }

    function _word(bytes32 tag) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tag))) | 1;
    }

    /// @dev Day 400 puts every seeded slot far past the deploy program — the cold, worst-case shape.
    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    function _seed(PurchaseDailySeeder.Shape memory s) internal {
        _deployProtocol();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(s.word);
        uint8[4] memory bonusT =
            JackpotBucketLib.getRandomTraits(EntropyLib.hash2(s.word, uint256(keccak256("BONUS_TRAITS"))));

        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(PurchaseDailySeeder).runtimeCode);
        PurchaseDailySeeder(payable(address(game))).seedPurchaseDaily(s, mainT, bonusT);
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

    /// @dev One advanceGame tx: gas used and a tally of what it emitted.
    function _measure() internal returns (uint256 used, Tally memory t) {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame();
        used = g0 - gasleft();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        delete lastLogs;
        for (uint256 i; i < logs.length; ++i) lastLogs.push(logs[i]);
        address[] memory ethW = new address[](PURCHASE_ETH_WINNERS + 8);
        address[] memory tkW = new address[](PURCHASE_PHASE_TICKET_MAX_WINNERS + 8);
        address[] memory flW = new address[](DAILY_COIN_MAX_WINNERS + 8);
        address[] memory farW = new address[](FAR_FUTURE_FLIP_SAMPLES + 8);
        for (uint256 i; i < logs.length; ++i) {
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
                if (_pushDistinct(flW, t.flipWins, w)) ++t.flipDistinct;
                ++t.flipWins;
            } else if (t0 == FAR_WIN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[1])));
                if (_pushDistinct(farW, t.farWins, w)) ++t.farDistinct;
                ++t.farWins;
            } else if (t0 == COMP_WIN_SIG) {
                ++t.compWins;
            } else if (t0 == BAF_ARMED_SIG) {
                t.bafArmed = true;
            } else if (t0 == ADVANCE_SIG) {
                (t.stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        emit log_named_uint("headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
        emit log_named_uint(
            "distance_to_10M_target", used < GAS_TARGET ? GAS_TARGET - used : 0
        );
        emit log_named_uint("over_10M_target_by", used > GAS_TARGET ? used - GAS_TARGET : 0);
    }

    /// @dev Appends `w` at `n` and reports whether it was unseen among the first `n` (O(n^2), n <= 120).
    function _pushDistinct(address[] memory arr, uint256 n, address w) private pure returns (bool fresh) {
        fresh = true;
        for (uint256 j; j < n; ++j) {
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
        emit log_named_uint("  flip_near_wins", t.flipWins);
        emit log_named_uint("  flip_near_distinct_winners", t.flipDistinct);
        emit log_named_uint("  flip_far_wins", t.farWins);
        emit log_named_uint("  flip_far_distinct_winners", t.farDistinct);
        emit log_named_uint("  craps_comp_wins", t.compWins);
        emit log_named_uint("  baf_armed", t.bafArmed ? 1 : 0);
    }
}

/// @notice HEADLINE: 49 ETH + 120 ticket + 50 near-FLIP + 8 far-FLIP winners, target-met latch + BAF arm.
contract PurchaseDailyWorstCase is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_LATCH, PREV_POOL));
    }

    function test_PurchaseDaily_49Eth_120Tickets_58Flip_Latch_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_FULL (stage 6): 49 ETH, priced tickets, 50+8 FLIP, latch + BAF arm", used, t);
        emit log_named_uint("PURCHASE_DAILY_STAGE_WORST_CASE_GAS", used);

        // Non-vacuity: every leg MUST have run at its cap, or the ceiling is not one.
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "the ETH leg paid all 49 fixed-bucket winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins, DAILY_COIN_MAX_WINNERS, "the near-FLIP leg paid all 50 pulls");
        assertEq(t.farWins, FAR_FUTURE_FLIP_SAMPLES, "the far-FLIP leg paid all 8 samples");
        assertEq(t.compWins, 0, "no comp mode at this FLIP budget");
        assertFalse(t.bafArmed, "the latch waits for the sealing ticket stage");
        // Sampling is with replacement: nearly every winner must still be a distinct cold address.
        assertEq(t.ethDistinct, 49, "all ETH winners are distinct cold addresses");
        assertGe(t.flipDistinct, 48, "at least 48 of the 50 near-FLIP winners are distinct cold addresses");

        assertLt(used, EIP7825_TX_GAS_CAP, "PURCHASE DAILY: the full stage must clear EIP-7825");

        // The ticket leg rides the next advance on the same recorded word and seals the day.
        (uint256 ticketUsed, Tally memory tk) = _measure();
        _emitTally("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", ticketUsed, tk);
        emit log_named_uint("PURCHASE_DAILY_TICKET_STAGE_WORST_CASE_GAS", ticketUsed);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ethWins + tk.flipWins + tk.farWins + tk.compWins, 0, "only the ticket leg rides the ticket stage");
        assertEq(tk.ticketDistinct, 120, "all ticket winners are distinct cold addresses");
        assertTrue(tk.bafArmed, "the sealing ticket stage latched last purchase day and armed the BAF draw");
        assertLt(ticketUsed, EIP7825_TX_GAS_CAP, "TICKET STAGE: clears EIP-7825");
    }
}

/// @notice Same caps with the latch quiet (next pool under target): the stage without the BAF arm.
contract PurchaseDailyNoLatch is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_QUIET, PREV_POOL));
    }

    function test_PurchaseDaily_AllCaps_NoLatch_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_NO_LATCH (stage 6): 49 ETH, priced tickets, 50+8 FLIP", used, t);
        emit log_named_uint("PURCHASE_DAILY_NO_LATCH_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins, DAILY_COIN_MAX_WINNERS, "50 near-FLIP pulls");
        assertEq(t.farWins, FAR_FUTURE_FLIP_SAMPLES, "8 far-FLIP samples");
        assertFalse(t.bafArmed, "no latch: no BAF arm");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");

        // The ticket leg rides the next advance on the same recorded word and seals the day.
        (uint256 ticketUsed, Tally memory tk) = _measure();
        _emitTally("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", ticketUsed, tk);
        emit log_named_uint("PURCHASE_DAILY_NO_LATCH_TICKET_STAGE_GAS", ticketUsed);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ethWins + tk.flipWins + tk.farWins + tk.compWins, 0, "only the ticket leg rides the ticket stage");
        assertFalse(tk.bafArmed, "no latch: no BAF arm");
        assertLt(ticketUsed, EIP7825_TX_GAS_CAP, "TICKET STAGE: clears EIP-7825");
    }
}

/// @notice SPLIT (a): ETH + ticket legs only — the FLIP boards empty (the 60 pulls still walk, no credit).
contract PurchaseDailyEthTicketsOnly is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, 0, 0, NEXT_POOL_QUIET, PREV_POOL));
    }

    function test_PurchaseDaily_49Eth_120Tickets_NoFlipWinners_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_ETH_TICKETS_ONLY (stage 6): 49 ETH, priced tickets, empty FLIP boards", used, t);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins, 0, "no near-FLIP winner drawn");
        assertEq(t.farWins, 0, "no far-FLIP winner drawn");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");

        // The ticket leg rides the next advance on the same recorded word and seals the day.
        (uint256 ticketUsed, Tally memory tk) = _measure();
        _emitTally("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", ticketUsed, tk);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_TICKET_STAGE_GAS", ticketUsed);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ethWins + tk.flipWins + tk.farWins + tk.compWins, 0, "only the ticket leg rides the ticket stage");
        assertLt(ticketUsed, EIP7825_TX_GAS_CAP, "TICKET STAGE: clears EIP-7825");
    }
}

/// @notice SPLIT (b): the FLIP legs only — the main board empty (ETH and ticket legs draw no winner).
contract PurchaseDailyFlipOnly is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(0, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_QUIET, PREV_POOL));
    }

    function test_PurchaseDaily_NoEthNoTickets_58Flip_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_FLIP_ONLY (stage 6): empty main board, 50+8 FLIP", used, t);
        emit log_named_uint("PURCHASE_DAILY_FLIP_LEGS_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, 0, "no ETH winner drawn");
        assertEq(t.ticketWins, 0, "no ticket winner drawn");
        assertEq(t.flipWins, DAILY_COIN_MAX_WINNERS, "50 near-FLIP pulls");
        assertEq(t.farWins, FAR_FUTURE_FLIP_SAMPLES, "8 far-FLIP samples");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @notice COMP-MODE BRANCH: a FLIP budget funding 6 whole Craps day passes turns one quadrant's
///         pulls into up to 6 creditPasses calls on the real table (the other branch of the FLIP leg).
contract PurchaseDailyCompMode is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_QUIET, PREV_POOL_COMP));
    }

    function test_PurchaseDaily_AllCaps_CompMode_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_COMP_MODE (stage 6): 49 ETH, priced tickets, comp quadrant + FLIP", used, t);
        emit log_named_uint("PURCHASE_DAILY_COMP_MODE_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.compWins, 6, "the comp quadrant banked all 6 comp slots");
        // 37 or 38 non-comp pulls remain depending on which quadrant went comp.
        assertGe(t.flipWins, 37, "the non-comp quadrants still paid every scheduled pull");
        assertEq(t.farWins, FAR_FUTURE_FLIP_SAMPLES, "8 far-FLIP samples");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");

        // The ticket leg rides the next advance on the same recorded word and seals the day.
        (uint256 ticketUsed, Tally memory tk) = _measure();
        _emitTally("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", ticketUsed, tk);
        emit log_named_uint("PURCHASE_DAILY_COMP_MODE_TICKET_STAGE_GAS", ticketUsed);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ethWins + tk.flipWins + tk.farWins + tk.compWins, 0, "only the ticket leg rides the ticket stage");
        assertLt(ticketUsed, EIP7825_TX_GAS_CAP, "TICKET STAGE: clears EIP-7825");
    }
}

/// @notice TRUE CEILING: the headline shape with the day's word NOT pre-recorded — the measured tx
///         applies the freshly fulfilled VRF word (coinflip payouts, quest roll, craps bonus-day open,
///         lootbox finalize) and then pays the whole purchase daily.
contract PurchaseDailyWithRngApply is PurchaseDailyFixture, FreshWordLeg {
    function setUp() public {
        PurchaseDailySeeder.Shape memory s = _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_LATCH, PREV_POOL);
        _seedFresh(s);
        _armFreshWord(s.word, 400);
    }

    function test_PurchaseDaily_AllCaps_WithRngApplyLeg_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_WITH_RNG_APPLY (stage 6): word applied + 49 ETH, priced tickets, 50+8 FLIP, latch", used, t);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(lastLogs);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        emit log_named_uint("PURCHASE_DAILY_TRUE_CEILING_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran in the word-apply tx");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins, DAILY_COIN_MAX_WINNERS, "50 near-FLIP pulls");
        assertEq(t.farWins, FAR_FUTURE_FLIP_SAMPLES, "8 far-FLIP samples");
        assertEq(t.ethDistinct, 49, "all ETH credits are fresh recipient writes");
        assertEq(t.flipDistinct, 50, "all near-FLIP credits are fresh recipient writes");
        assertFalse(t.bafArmed, "the latch waits for the sealing ticket stage");
        assertGe(cfLogs, 1, "coinflip.processCoinflipPayouts ran in the measured tx");
        assertGe(crLogs, 8, "craps openBonusDay opened the day's 7 windows in the measured tx");
        assertLt(used, EIP7825_TX_GAS_CAP, "TRUE CEILING: purchase daily incl. word apply clears EIP-7825");

        // The ticket leg rides the next advance on the same recorded word and seals the day.
        (uint256 ticketUsed, Tally memory tk) = _measure();
        _emitTally("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", ticketUsed, tk);
        emit log_named_uint("PURCHASE_DAILY_TRUE_CEILING_TICKET_STAGE_GAS", ticketUsed);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ethWins + tk.flipWins + tk.farWins + tk.compWins, 0, "only the ticket leg rides the ticket stage");
        assertEq(tk.ticketDistinct, 120, "all ticket winners are distinct cold addresses");
        assertTrue(tk.bafArmed, "the sealing ticket stage latched last purchase day and armed the BAF draw");
        assertLt(ticketUsed, EIP7825_TX_GAS_CAP, "TICKET STAGE: clears EIP-7825");
    }
}

/// @notice TRUE CEILING of the jackpot-phase day-1 ETH stage (tx1, stage 10): word applied in the same tx.
contract JackpotDayOneWithRngApply is DayOneFixture, FreshWordLeg {
    Vm.Log[] internal dayOneLogs;

    function setUp() public {
        uint256 word = _allGoldWord("jackpot-day-one-gold");
        _deployProtocol();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(word);
        uint8[4] memory bonusT =
            JackpotBucketLib.getRandomTraits(EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS"))));
        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(DayOneUnrecordedSeeder).runtimeCode);
        DayOneUnrecordedSeeder(payable(address(game))).seedDayOne(LVL, word, mainT, bonusT, BASE, ETH_HOLDERS, EB_HOLDERS, true);
        DayOneUnrecordedSeeder(payable(address(game))).unrecordWord();
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
        _armFreshWord(word, 400);
    }

    function test_DayOne_305Eth_AllGold_GoldenGrand_WithRngApplyLeg_Measured() public {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame();
        uint256 used = g0 - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint8 stage = 255;
        uint256 ethWins;
        bool grand;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            if (t0 == ETH_WIN_SIG) ++ethWins;
            else if (t0 == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            else if (t0 == GOLDEN_WIN_SIG) {
                (,, bool g,,,,) = abi.decode(logs[i].data, (uint8, uint8, bool, uint256, uint256, uint256, uint256));
                grand = g;
            }
        }
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(logs);
        emit log_string("DAY1_WITH_RNG_APPLY tx1 (stage 10): word applied + 305 ETH, all-gold, golden grand");
        emit log_named_uint("  advance_gas", used);
        emit log_named_uint("  stage", stage);
        emit log_named_uint("  eth_wins", ethWins);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        emit log_named_uint("headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
        emit log_named_uint("JACKPOT_DAY1_ETH_STAGE_TRUE_CEILING_GAS", used);

        assertEq(stage, STAGE_JACKPOT_DAILY_STARTED, "the day-1 ETH stage ran in the word-apply tx");
        assertEq(ethWins, DAILY_ETH_MAX_WINNERS, "305 ETH winners");
        assertTrue(grand, "golden grand resolved");
        assertGe(cfLogs, 1, "coinflip payouts ran in the measured tx");
        assertGe(crLogs, 8, "craps bonus day opened in the measured tx");
        assertLt(used, EIP7825_TX_GAS_CAP, "TRUE CEILING: day-1 ETH stage incl. word apply clears EIP-7825");
    }
}
