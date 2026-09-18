// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title JackpotDayOneWorstCase — the per-tx gas ceiling of the jackpot-phase DAY-1 daily.
/// @notice The early-bird day (`jackpotCounter == 0`) carries TWO winner-capped legs, each from its
///         own advance tx:
///           - STAGE_JACKPOT_DAILY_STARTED (10): `_processDailyEth` at the DAILY_ETH_MAX_WINNERS = 305
///             cap (buckets 159/95/50/1 once `dailyEthBudget >= JACKPOT_SCALE_SECOND_WEI = 200 ETH`),
///             which also prices the early-bird budget (3% of futurePrizePool, moved future -> next)
///             and latches its entry count; then
///           - STAGE_JACKPOT_EARLY_BIRD_TICKETS (14): `payEarlyBirdTickets` at the
///             TICKET_JACKPOT_MAX_WINNERS = 100 cap (25 per bonus quadrant of lvl+1, once the 3%
///             covers 100 tickets at priceForLevel(lvl+1)).
///         The other two 100-winner ticket legs of the same daily likewise run from their own stages
///         (payDailyJackpotCoinAndTickets, payCarryoverTickets). This suite measures BOTH txs on the
///         REAL advanceGame bytecode at every cap, with every winner a distinct address holding no
///         claimable / no queued entries (cold SSTOREs), on the worst ETH-leg branch (all-gold board
///         -> golden-ticket arm on the solo winner + the solo whale-pass path) with an armed golden
///         ticket resolving as a GRAND in the same call, and asserts each tx under the EIP-7825 cap.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding happens in setUp() — a SEPARATE
///      transaction from the measured body — so the measured call starts on a cold EIP-2929 access
///      list, as a real keeper tx would (the Lvl100PhaseEndAdvanceGas pattern). The winner sampler
///      draws WITH replacement, so a handful of the 305 ETH draws may repeat a holder; the suite counts
///      distinct winners and reports the fully-cold top-up from the measured per-fresh-winner marginal.
contract DayOneSeeder is DegenerusGame, BucketSeed {
    /// @notice The day-1 (early-bird) jackpot-phase pre-state, at every cap the stage can reach.
    /// @param lvl         the level whose jackpot phase is on day 1
    /// @param word        the day's recorded VRF word (non-zero -> rngGate returns it immediately)
    /// @param mainTraits  the 4 traits the main board draws (ETH leg, sampled from lvlTraitEntry[lvl])
    /// @param bonusTraits the 4 traits the bonus board draws (early-bird leg, sampled from lvlTraitEntry[lvl+1])
    /// @param base        disjoint address-space base for synthetic holders
    /// @param ethHolders  distinct holders per main-board bucket (0 disables the ETH draw's buckets)
    /// @param ebHolders   distinct holders per bonus-board bucket (0 leaves the early-bird draw with no bucket)
    /// @param armGolden   arm a golden ticket on quadrant 0 with the board's symbol so it resolves this draw
    function seedDayOne(
        uint24 lvl,
        uint256 word,
        uint8[4] calldata mainTraits,
        uint8[4] calldata bonusTraits,
        uint160 base,
        uint256 ethHolders,
        uint256 ebHolders,
        bool armGolden
    ) external {
        uint24 day = _simulatedDayIndex();

        // The shared jackpot-phase day shape: day == dailyIdx + 1, the day's request still locked
        // (subscriber STAGE skipped), read slot drained, no carryover leg or coin/ticket leg pending.
        level = lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        lastPurchaseDay = false;
        compressedJackpotFlag = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        jackpotCounter = 0; // day 1 == the early-bird day
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = word;
        rngWordByDay[day] = word;
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
        levelPrizePool[lvl] = 1000 ether;
        levelPrizePool[lvl - 1] = 1000 ether;

        // ETH budget = curPool * dailyBps(6..14%) * 80% must reach the 200 ETH max-scale floor at the
        // 6% floor: 6000 * 0.06 * 0.8 = 288 ETH >= 200 -> 305 winners on every word.
        currentPrizePool = uint128(6000 ether);
        // Early-bird budget = 3% of futurePrizePool; 100 tickets at priceForLevel(lvl+1) = 0.04 ETH
        // need >= 133.4 ETH of future pool even after a golden grand takes its 25% first.
        _setPrizePools(uint128(50 ether), uint128(1000 ether));

        for (uint8 q; q < 4; ++q) {
            if (ethHolders != 0) {
                _seedBucketDistinct(lvl, mainTraits[q], ethHolders, base + uint160(q) * 0x100000);
            }
            if (ebHolders != 0) {
                _seedBucketDistinct(lvl + 1, bonusTraits[q], ebHolders, base + 0x800000 + uint160(q) * 0x100000);
            }
        }

        if (armGolden) {
            // Armed on the prior day (dailyIdx > arm day) for quadrant 0 with the board's own
            // symbol, so an all-gold board resolves it as the GRAND in this same call.
            goldenTicket =
                uint256(uint160(base + 0xF00000)) |
                (uint256(0) << 160) |
                (uint256(mainTraits[0] & 7) << 162) |
                (uint256(dailyIdx - 1) << 165) |
                (uint256(1) << 189);
        }
    }
}

/// @dev Shared measurement seam: warp, etch-seed-restore, drive the live advanceGame, classify winners.
abstract contract DayOneFixture is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this is a permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev The 10M soft design target the drains are sized to (USER dual bound).
    uint256 internal constant GAS_TARGET = 10_000_000;

    bytes32 internal constant ETH_WIN_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant WHALE_PASS_SIG = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
    bytes32 internal constant GOLDEN_WIN_SIG =
        keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)");
    bytes32 internal constant GOLDEN_ARMED_SIG = keccak256("GoldenTicketArmed(address,uint24,uint8,uint8)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_DAILY_STARTED = 10;
    uint8 internal constant STAGE_JACKPOT_EARLY_BIRD_TICKETS = 14;
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;
    uint16 internal constant TICKET_JACKPOT_MAX_WINNERS = 100;

    uint24 internal constant LVL = 110;
    uint160 internal constant BASE = uint160(0x1000000000);
    uint256 internal constant ETH_HOLDERS = 5000; // per main-board bucket: 159 draws repeat ~2.5x
    uint256 internal constant EB_HOLDERS = 2000; // per bonus-board bucket: 25 draws repeat ~0.16x

    struct Tally {
        uint8 stage;
        uint256 ethWins;
        uint256 ethDistinct;
        uint256 ticketWins;
        uint256 ticketDistinct;
        uint256 whalePassWins;
        bool goldenArmed;
        bool goldenGrand;
    }

    /// @dev Bits 3-5 of each 6-bit quadrant trait are the color; 7 (all set) is gold.
    uint256 internal constant GOLD_MASK = (uint256(0x38) << 0) | (uint256(0x38) << 6) | (uint256(0x38) << 12)
        | (uint256(0x38) << 18);

    function _allGoldWord(bytes32 tag) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(tag))) | GOLD_MASK;
    }

    function _plainWord(bytes32 tag) internal pure returns (uint256) {
        // Clear one color bit per quadrant so no quadrant is gold (the typical branch).
        return (uint256(keccak256(abi.encodePacked(tag))) & ~GOLD_MASK) | 1;
    }

    /// @dev Day 400 puts every seeded slot far past the deploy program — the cold, worst-case shape.
    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    function _seed(uint256 word, uint256 ethHolders, uint256 ebHolders, bool armGolden) internal {
        _deployProtocol();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(word);
        uint8[4] memory bonusT =
            JackpotBucketLib.getRandomTraits(EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS"))));

        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(DayOneSeeder).runtimeCode);
        DayOneSeeder(payable(address(game))).seedDayOne(LVL, word, mainT, bonusT, BASE, ethHolders, ebHolders, armGolden);
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
    }

    /// @dev One advanceGame tx: gas used and a tally of what it emitted.
    function _measure() internal returns (uint256 used, Tally memory t) {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame();
        used = g0 - gasleft();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        address[] memory ethW = new address[](DAILY_ETH_MAX_WINNERS + 8);
        address[] memory tkW = new address[](TICKET_JACKPOT_MAX_WINNERS + 8);
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
            } else if (t0 == WHALE_PASS_SIG) {
                ++t.whalePassWins;
            } else if (t0 == GOLDEN_ARMED_SIG) {
                t.goldenArmed = true;
            } else if (t0 == GOLDEN_WIN_SIG) {
                // data: route, goldCount, grand, ethAmount, halfPassCount, flipCredit, wwxrpAmount
                (,, bool grand,,,,) =
                    abi.decode(logs[i].data, (uint8, uint8, bool, uint256, uint256, uint256, uint256));
                t.goldenGrand = grand;
            } else if (t0 == ADVANCE_SIG) {
                (t.stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        emit log_named_uint("headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
    }

    /// @dev Appends `w` at `n` and reports whether it was unseen among the first `n` (O(n^2), n <= 305).
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

    /// @dev Check the split sequence with two calls in one test transaction. The second call
    ///      inherits warm accesses and dirty slots, so its gas is diagnostic only; the separate
    ///      JackpotDayOneEarlyBirdCold fixture measures stage 14 from a fresh transaction.
    function _measureBoth() internal returns (uint256 used1, Tally memory t1, uint256 used2, Tally memory t2) {
        (used1, t1) = _measure();
        assertEq(t1.stage, STAGE_JACKPOT_DAILY_STARTED, "tx 1: the day-1 ETH stage ran");
        assertEq(t1.ticketWins, 0, "tx 1: the early-bird leg did not run in the ETH stage's tx");
        (used2, t2) = _measure();
        assertEq(t2.stage, STAGE_JACKPOT_EARLY_BIRD_TICKETS, "tx 2: the early-bird stage ran next");
        assertEq(t2.ethWins, 0, "tx 2: no ETH leg in the early-bird stage's tx");
        assertEq(t2.whalePassWins, 0, "tx 2: no whale pass in the early-bird stage's tx");
        assertFalse(t2.goldenArmed || t2.goldenGrand, "tx 2: no golden-ticket activity in the early-bird stage's tx");
    }

    function _emitTally(string memory label, uint256 used, Tally memory t) internal {
        emit log_string(label);
        emit log_named_uint("  advance_gas", used);
        emit log_named_uint("  stage", t.stage);
        emit log_named_uint("  eth_wins", t.ethWins);
        emit log_named_uint("  eth_distinct_winners", t.ethDistinct);
        emit log_named_uint("  ticket_wins", t.ticketWins);
        emit log_named_uint("  ticket_distinct_winners", t.ticketDistinct);
        emit log_named_uint("  whale_pass_wins", t.whalePassWins);
        emit log_named_uint("  golden_armed", t.goldenArmed ? 1 : 0);
        emit log_named_uint("  golden_grand", t.goldenGrand ? 1 : 0);
    }
}

/// @notice HEADLINE: day-1 stage at 305 ETH winners + 100 early-bird winners, all-gold board, golden grand.
contract JackpotDayOneWorstCase is DayOneFixture {
    function setUp() public {
        _seed(_allGoldWord("jackpot-day-one-gold"), ETH_HOLDERS, EB_HOLDERS, true);
    }

    function test_DayOne_305Eth_100EarlyBird_AllGold_GoldenGrand_Measured() public {
        (uint256 used1, Tally memory t1, uint256 used2, Tally memory t2) = _measureBoth();
        _emitTally("DAY1_FULL tx1 (stage 10): 305 ETH, all-gold, golden grand", used1, t1);
        _emitTally("DAY1_FULL tx2 (stage 14): 100 early-bird", used2, t2);
        emit log_named_uint("JACKPOT_DAY1_ETH_STAGE_WORST_CASE_GAS", used1);
        emit log_named_uint("JACKPOT_DAY1_EARLY_BIRD_STAGE_WORST_CASE_GAS", used2);
        emit log_named_uint("JACKPOT_DAY1_BOTH_STAGES_SUM_GAS", used1 + used2);

        // Non-vacuity: each leg MUST have run at its cap on the worst branch, or the ceiling is
        // not one.
        assertEq(t1.ethWins, DAILY_ETH_MAX_WINNERS, "the ETH leg paid the full 305-winner cap");
        assertEq(t2.ticketWins, TICKET_JACKPOT_MAX_WINNERS, "the early-bird leg paid the full 100-winner cap");
        assertEq(t1.whalePassWins, 1, "the solo bucket took the whale-pass path");
        assertTrue(t1.goldenArmed, "the all-gold board armed a golden ticket on the solo winner");
        assertTrue(t1.goldenGrand, "the armed golden ticket resolved as the grand in the same call");
        // Sampling is with replacement: nearly every winner must still be a distinct cold address.
        assertGe(t1.ethDistinct, 295, "at least 295 of the 305 ETH winners are distinct cold addresses");
        assertGe(t2.ticketDistinct, 97, "at least 97 of the 100 early-bird winners are distinct cold addresses");

        assertLt(used1, EIP7825_TX_GAS_CAP, "DAY-1 ETH STAGE: 305 ETH winners must clear EIP-7825");
        assertLt(used2, EIP7825_TX_GAS_CAP, "DAY-1 EARLY-BIRD STAGE: 100 ticket winners must clear EIP-7825");
        assertLt(used2, GAS_TARGET, "the early-bird stage alone sits under the 10M design target");
    }
}

/// @notice SPLIT (a): the same shape with the early-bird board empty — the ETH stage + fixed overhead
///         alone, then an early-bird stage that still runs (the budget was priced) but draws no winner.
contract JackpotDayOneEthLegOnly is DayOneFixture {
    function setUp() public {
        _seed(_allGoldWord("jackpot-day-one-gold"), ETH_HOLDERS, 0, true);
    }

    function test_DayOne_305Eth_NoEarlyBirdWinners_Measured() public {
        (uint256 used1, Tally memory t1, uint256 used2, Tally memory t2) = _measureBoth();
        _emitTally("DAY1_ETH_ONLY tx1 (stage 10): 305 ETH, all-gold, golden grand", used1, t1);
        _emitTally("DAY1_ETH_ONLY tx2 (stage 14): empty early-bird board", used2, t2);
        emit log_named_uint("JACKPOT_DAY1_ETH_LEG_ONLY_GAS", used1);
        emit log_named_uint("JACKPOT_DAY1_EMPTY_EARLY_BIRD_STAGE_GAS", used2);

        assertEq(t1.ethWins, DAILY_ETH_MAX_WINNERS, "the ETH leg paid the full 305-winner cap");
        assertEq(t2.ticketWins, 0, "no early-bird winner was drawn");
        assertTrue(t1.goldenGrand, "the golden grand still resolved");
        assertLt(used1, EIP7825_TX_GAS_CAP, "ETH stage alone clears EIP-7825");
        assertLt(used2, EIP7825_TX_GAS_CAP, "empty early-bird stage clears EIP-7825");
    }
}

/// @notice SPLIT (b): the early-bird leg with the main board empty — 100 ticket winners + fixed overhead.
contract JackpotDayOneEarlyBirdOnly is DayOneFixture {
    function setUp() public {
        _seed(_allGoldWord("jackpot-day-one-gold"), 0, EB_HOLDERS, true);
    }

    function test_DayOne_NoEth_100EarlyBird_Measured() public {
        (uint256 used1, Tally memory t1, uint256 used2, Tally memory t2) = _measureBoth();
        _emitTally("DAY1_EB_ONLY tx1 (stage 10): empty main board, all-gold, golden grand", used1, t1);
        _emitTally("DAY1_EB_ONLY tx2 (stage 14): 100 early-bird", used2, t2);
        emit log_named_uint("JACKPOT_DAY1_EMPTY_ETH_STAGE_GAS", used1);
        emit log_named_uint("JACKPOT_DAY1_EARLY_BIRD_LEG_ONLY_GAS", used2);

        assertEq(t1.ethWins, 0, "no ETH winner was drawn");
        assertEq(t2.ticketWins, TICKET_JACKPOT_MAX_WINNERS, "the early-bird leg paid the full 100-winner cap");
        assertLt(used1, EIP7825_TX_GAS_CAP, "empty ETH stage clears EIP-7825");
        assertLt(used2, EIP7825_TX_GAS_CAP, "early-bird stage alone clears EIP-7825");
    }
}

/// @notice TYPICAL BRANCH: no gold quadrant (no golden arm, no golden resolve), otherwise both caps.
contract JackpotDayOnePlainBoard is DayOneFixture {
    function setUp() public {
        _seed(_plainWord("jackpot-day-one-plain"), ETH_HOLDERS, EB_HOLDERS, false);
    }

    function test_DayOne_305Eth_100EarlyBird_PlainBoard_Measured() public {
        (uint256 used1, Tally memory t1, uint256 used2, Tally memory t2) = _measureBoth();
        _emitTally("DAY1_PLAIN tx1 (stage 10): 305 ETH, no gold, no golden ticket", used1, t1);
        _emitTally("DAY1_PLAIN tx2 (stage 14): 100 early-bird", used2, t2);
        emit log_named_uint("JACKPOT_DAY1_ETH_STAGE_PLAIN_BOARD_GAS", used1);
        emit log_named_uint("JACKPOT_DAY1_EARLY_BIRD_STAGE_PLAIN_BOARD_GAS", used2);

        assertEq(t1.ethWins, DAILY_ETH_MAX_WINNERS, "the ETH leg paid the full 305-winner cap");
        assertEq(t2.ticketWins, TICKET_JACKPOT_MAX_WINNERS, "the early-bird leg paid the full 100-winner cap");
        assertFalse(t1.goldenArmed, "no gold quadrant: no golden arm");
        assertFalse(t1.goldenGrand, "no armed ticket: no golden resolve");
        assertLt(used1, EIP7825_TX_GAS_CAP, "plain-board day-1 ETH stage clears EIP-7825");
        assertLt(used2, EIP7825_TX_GAS_CAP, "plain-board early-bird stage clears EIP-7825");
    }
}

/// @notice Measure stage 14 in a separate transaction from the stage that wrote its budget.
contract JackpotDayOneEarlyBirdCold is DayOneFixture {
    function setUp() public {
        _seed(_allGoldWord("jackpot-day-one-gold"), ETH_HOLDERS, EB_HOLDERS, true);
        game.advanceGame();
    }

    function test_EarlyBirdStageColdAfterCompletedEthStage() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("DAY1_EARLY_BIRD_COLD: stage 10 committed in setUp", used, t);
        assertEq(t.stage, STAGE_JACKPOT_EARLY_BIRD_TICKETS, "stage 14 must run next");
        assertEq(t.ticketWins, TICKET_JACKPOT_MAX_WINNERS, "all 100 ticket awards must run");
        assertGe(t.ticketDistinct, 97, "at least 97 cold ticket recipients");
        assertEq(t.ethWins, 0, "the ETH stage must not repeat");
        assertFalse(t.goldenArmed || t.goldenGrand, "golden-ticket processing must not repeat");
        assertLt(used, GAS_TARGET, "the cold early-bird stage must stay below 10M gas");
    }
}
