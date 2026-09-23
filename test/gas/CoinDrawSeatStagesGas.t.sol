// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title CoinDrawSeatStagesGas — the jackpot-phase COIN+TICKETS stage with the coin draw at max seats.
/// @notice STAGE_JACKPOT_COIN_TICKETS (8) / STAGE_JACKPOT_PHASE_ENDED (9) run
///         `payDailyJackpotCoinAndTickets` in one advanceGame tx:
///           - the L+1 bonus-trait coin draw (`_runFlipJackpot(lvl, lvl, lvl+1, lvl+1)`), budget
///             B = levelPrizePool[lvl-1] * 1000 / (priceForLevel(lvl) * 400): the craps half seats up
///             to 25 winners on tomorrow's table (opener via vaultComp kind 5, whole-day upgrade via
///             deliverPasses), the coin half pays up to 25 shares in one creditFlipBatch;
///           - the daily ticket distribution to the current level's main-trait winners
///             (TICKET_JACKPOT_MAX_WINNERS = 96), each a fresh registry + queue + owed write;
///           - on the final day, `_endPhase` (and a priced carryover leg for the next stage).
///         Every seat lands on a distinct never-touched wallet — all 25 whole days (B >= 1.14M FLIP) or
///         all 25 openers (B = 130,000 FLIP, the heavier composition: an opener seat's window
///         reservation costs more than a whole-day seat) — every ticket
///         winner is a distinct never-touched wallet, through the full DeployProtocol wiring (real
///         Game, real CrapsBattle, real Coinflip). The call is capped at the EIP-7825 limit less
///         intrinsic; the figure includes the 21,064 intrinsic.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding in setUp() — a separate tx — so the
///      measured call starts cold (the Lvl100PhaseEndAdvanceGas / JackpotTicketStagesGas pattern).
///      The coin+tickets stage never shares a tx with the word-apply leg: the day's word is applied
///      by the ETH stage (STAGE_JACKPOT_DAILY_STARTED) two advances earlier.
contract CoinSeatJackpotSeeder is DegenerusGame, BucketSeed {
    struct Shape {
        uint24 lvl;
        uint256 word;
        uint8 counter; // jackpotCounter on entry: JACKPOT_DAYS - 1 is the final (phase-ending) day
        uint256 carryoverEntries; // priced carryover leg (paid by the NEXT stage)
        uint256 prevPool; // levelPrizePool[lvl - 1]: the coin budget
        uint256 ticketHolders; // distinct holders per main-trait bucket at lvl (ticket leg)
        uint256 coinHolders; // distinct holders per bonus-trait bucket at lvl + 1 (coin draw)
        uint160 base;
    }

    function seed(Shape calldata s, uint8[4] calldata mainTraits, uint8[4] calldata bonusTraits) external {
        uint24 day = _simulatedDayIndex();
        level = s.lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        lastPurchaseDay = false;
        jackpotFlags = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        jackpotCounter = s.counter;
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = s.word;
        rngWordByDay[day] = s.word;
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = true;
        // 4000 daily entries = 1000 whole tickets: the 96-winner cap saturates.
        dailyTicketBudgetsPacked = uint256(1) | (uint256(4000) << 8) | (s.carryoverEntries << 72);
        levelPrizePool[s.lvl] = 1000 ether;
        levelPrizePool[s.lvl - 1] = s.prevPool;
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = uint128(200 ether);

        // Genesis deities add virtual entries naming VAULT / sDGNRS, whose seats are refused (a
        // cheaper path): exclude them so every draw lands on a fresh wallet.
        deityBySymbol[VAULT_DEITY_SYMBOL] = address(0);
        deityBySymbol[SDGNRS_DEITY_SYMBOL] = address(0);

        for (uint24 L = s.lvl; L <= s.lvl + 1; ++L) {
            if (lvlEntryOwner[L].length == 0) lvlEntryOwner[L].push(EntryOwner(address(1), 0));
        }
        for (uint8 q; q < 4; ++q) {
            _seedBucketClear(s.lvl, mainTraits[q]);
            _seedBucketDistinct(s.lvl, mainTraits[q], s.ticketHolders, s.base + uint160(q) * 0x100000);
            _seedBucketClear(s.lvl + 1, bonusTraits[q]);
            _seedBucketDistinct(s.lvl + 1, bonusTraits[q], s.coinHolders, s.base + 0x800000 + uint160(q) * 0x100000);
        }
    }
}

abstract contract CoinSeatJackpotFixture is DeployProtocol {
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    uint256 internal constant GAS_TARGET = 10_000_000;
    uint256 internal constant INTRINSIC = 21_064;

    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant FAR_WIN_SIG = keccak256("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
    bytes32 internal constant CRAPS_WIN_SIG = keccak256("CoinDrawCrapsWin(address,uint24,bool,bool)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint256 internal constant TICKET_MAX = 96;
    uint256 internal constant HALF = 25;

    struct Tally {
        uint8 stage;
        uint256 tickets;
        uint256 ticketDistinct;
        uint256 shares;
        uint256 farShares;
        uint256 seats;
        uint256 days_;
        uint256 refused;
        uint256 coinDistinct;
    }

    function _shape() internal pure virtual returns (CoinSeatJackpotSeeder.Shape memory s);

    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    function setUp() public {
        _deployProtocol();
        CoinSeatJackpotSeeder.Shape memory s = _shape();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(s.word);
        uint8[4] memory bonusT =
            JackpotBucketLib.getRandomTraits(EntropyLib.hash2(s.word, uint256(keccak256("BONUS_TRAITS"))));
        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(CoinSeatJackpotSeeder).runtimeCode);
        CoinSeatJackpotSeeder(payable(address(game))).seed(s, mainT, bonusT);
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
    }

    function _measure() internal returns (uint256 used, Tally memory t) {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        used = g0 - gasleft() + INTRINSIC;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address[] memory tk = new address[](TICKET_MAX + 8);
        address[] memory cw = new address[](2 * HALF + 8);
        uint256 cn;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            if (t0 == TICKET_WIN_SIG) {
                if (_pushDistinct(tk, t.tickets, address(uint160(uint256(logs[i].topics[1]))))) ++t.ticketDistinct;
                ++t.tickets;
            } else if (t0 == FLIP_WIN_SIG) {
                if (_pushDistinct(cw, cn++, address(uint160(uint256(logs[i].topics[1]))))) ++t.coinDistinct;
                ++t.shares;
            } else if (t0 == FAR_WIN_SIG) {
                ++t.farShares;
            } else if (t0 == CRAPS_WIN_SIG) {
                if (_pushDistinct(cw, cn++, address(uint160(uint256(logs[i].topics[1]))))) ++t.coinDistinct;
                (bool fullDay, bool paidAsFlip) = abi.decode(logs[i].data, (bool, bool));
                ++t.seats;
                if (fullDay) ++t.days_;
                if (paidAsFlip) ++t.refused;
            } else if (t0 == ADVANCE_SIG) {
                (t.stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        emit log_named_uint("  tx_gas_incl_intrinsic", used);
        emit log_named_uint("  stage", t.stage);
        emit log_named_uint("  ticket_wins", t.tickets);
        emit log_named_uint("  ticket_distinct", t.ticketDistinct);
        emit log_named_uint("  coin_shares", t.shares);
        emit log_named_uint("  craps_seats", t.seats);
        emit log_named_uint("  craps_whole_days", t.days_);
        emit log_named_uint("  craps_refused", t.refused);
        emit log_named_uint("  coin_distinct_recipients", t.coinDistinct);
        emit log_named_uint("  headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
        emit log_named_uint("  over_10M_target_by", used > GAS_TARGET ? used - GAS_TARGET : 0);
    }

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

    function _assertCoinTickets(Tally memory t, uint8 stage, uint256 days_) internal {
        assertEq(t.stage, stage, "the coin+tickets stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.seats, HALF, "the coin draw drew all 25 seats");
        assertEq(t.days_, days_, "whole-day upgrades from the front");
        assertEq(t.refused, 0, "no seat refused");
        assertEq(t.shares, HALF, "the coin half paid 25 shares");
        assertEq(t.farShares, 0, "no fill draw in the jackpot phase");
        // With-replacement sampling over 5,000-holder buckets: allow one stray repeat.
        assertGe(t.coinDistinct, 2 * HALF - 1, "coin-draw recipients are distinct cold wallets");
    }
}

/// @notice Non-final jackpot day at L=110 (0.04 ETH): coin draw at 25 cold whole-day seats + 25 shares,
///         96 cold ticket winners, no carryover, the day seals in this stage.
contract JackpotCoinTicketsMaxSeats is CoinSeatJackpotFixture {
    function _shape() internal pure override returns (CoinSeatJackpotSeeder.Shape memory s) {
        s.lvl = 110;
        s.word = uint256(keccak256("coin-seat-jackpot-day")) | 1;
        s.counter = 1;
        s.carryoverEntries = 0;
        s.prevPool = 20_000 ether; // B = 1,250,000 FLIP at 0.04 ETH
        s.ticketHolders = 20_000;
        s.coinHolders = 5_000;
        s.base = uint160(0x1000000000);
    }

    function test_JackpotCoinTickets_25DaySeats_96Tickets_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_MAX_SEATS_GAS", used);
        _assertCoinTickets(t, STAGE_JACKPOT_COIN_TICKETS, HALF);
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @notice FINAL jackpot day at the x00 level L=100 (0.24 ETH): the same caps plus `_endPhase` and a
///         priced carryover leg (paid by the next stage; measured in Lvl100PhaseEndAdvanceGas).
contract JackpotCoinTicketsPhaseEndX00 is CoinSeatJackpotFixture {
    function _shape() internal pure override returns (CoinSeatJackpotSeeder.Shape memory s) {
        s.lvl = 100;
        s.word = uint256(keccak256("coin-seat-phase-end")) | 1;
        s.counter = 2;
        s.carryoverEntries = 4000;
        s.prevPool = 150_000 ether; // B = 1,562,500 FLIP at 0.24 ETH
        s.ticketHolders = 20_000;
        s.coinHolders = 5_000;
        s.base = uint160(0x1000000000);
    }

    function test_JackpotPhaseEnd_25DaySeats_96Tickets_EndPhase_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_PHASE_END_X00_MAX_SEATS_GAS", used);
        _assertCoinTickets(t, STAGE_JACKPOT_PHASE_ENDED, HALF);
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @notice FINAL jackpot day at an x0 level L=110: the same caps plus `_endPhase`.
contract JackpotCoinTicketsPhaseEndX0 is CoinSeatJackpotFixture {
    function _shape() internal pure override returns (CoinSeatJackpotSeeder.Shape memory s) {
        s.lvl = 110;
        s.word = uint256(keccak256("coin-seat-phase-end-x0")) | 1;
        s.counter = 2;
        s.carryoverEntries = 4000;
        s.prevPool = 20_000 ether;
        s.ticketHolders = 20_000;
        s.coinHolders = 5_000;
        s.base = uint160(0x1000000000);
    }

    function test_JackpotPhaseEnd_X0_25DaySeats_96Tickets_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_PHASE_END_X0_MAX_SEATS_GAS", used);
        _assertCoinTickets(t, STAGE_JACKPOT_PHASE_ENDED, HALF);
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @notice Non-final day at L=110 with the HEAVIER seat mix: 25 cold OPENER seats (B = 130,000 FLIP).
contract JackpotCoinTicketsOpeners is CoinSeatJackpotFixture {
    function _shape() internal pure override returns (CoinSeatJackpotSeeder.Shape memory s) {
        s.lvl = 110;
        s.word = uint256(keccak256("coin-seat-jackpot-day")) | 1;
        s.counter = 1;
        s.carryoverEntries = 0;
        s.prevPool = 2_080 ether; // B = 130,000 FLIP at 0.04 ETH: 25 openers, no upgrade
        s.ticketHolders = 20_000;
        s.coinHolders = 5_000;
        s.base = uint160(0x1000000000);
    }

    function test_JackpotCoinTickets_25OpenerSeats_96Tickets_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_OPENERS_GAS", used);
        _assertCoinTickets(t, STAGE_JACKPOT_COIN_TICKETS, 0);
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @notice FINAL day at the x00 level L=100 with 25 cold OPENER seats (B = 130,000 FLIP at 0.24 ETH).
contract JackpotCoinTicketsPhaseEndX00Openers is CoinSeatJackpotFixture {
    function _shape() internal pure override returns (CoinSeatJackpotSeeder.Shape memory s) {
        s.lvl = 100;
        s.word = uint256(keccak256("coin-seat-phase-end")) | 1;
        s.counter = 2;
        s.carryoverEntries = 4000;
        s.prevPool = 12_480 ether; // B = 130,000 FLIP at 0.24 ETH
        s.ticketHolders = 20_000;
        s.coinHolders = 5_000;
        s.base = uint160(0x1000000000);
    }

    function test_JackpotPhaseEnd_25OpenerSeats_96Tickets_EndPhase_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_PHASE_END_X00_OPENERS_GAS", used);
        _assertCoinTickets(t, STAGE_JACKPOT_PHASE_ENDED, 0);
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}
