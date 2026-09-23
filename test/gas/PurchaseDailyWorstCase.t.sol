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
/// @notice STAGE_PURCHASE_DAILY (6) pays the ETH leg, prices the ticket leg and runs the day's
///         coin draw(s) in one advanceGame tx; STAGE_PURCHASE_DAILY_TICKETS (15) pays the priced
///         ticket leg from the next advance on the same recorded word and seals the day. The legs:
///           - the daily ETH leg: fixed buckets [24,16,8,1] = 49 winners off the futurePrizePool
///             drip (`payDailyJackpot(false)` -> `_processDailyEth`);
///           - the daily ticket leg: priced here, paid in stage 15 at up to
///             PURCHASE_PHASE_TICKET_MAX_WINNERS = 120 winners;
///           - the purchase-day coin FILL draw (`payDailyFutureFlipJackpot` ->
///             `_awardFutureCoinFill`): up to 16 distinct level picks over the unminted far-future
///             queues [P+1, P+99], walking up to 25 CRAPS wallets + 25 COIN wallets. Budget
///             B = levelPrizePool[P-1] * 1000 / (price * 400). The craps half seats up to 25
///             winners on TOMORROW's table (opener via CrapsBattle.vaultComp kind 5 at 2,400 FLIP;
///             the half's leftover upgrades seats from the front to the whole day via
///             CrapsBattle.deliverPasses at +20,400), each seat preceded by an extsload of the
///             table's `_daySeated`; the coin half pays up to 25 equal shares in ONE
///             coinflip.creditFlipBatch. 25 seats at B >= 120,000 FLIP; all 25 whole days at
///             B >= 1,140,000 FLIP.
///           - LEVEL 1 only (P == 1): no ETH / ticket leg; instead a trait draw over
///             lvlTraitEntry[1] (`payDailyFlipJackpot`) AND the fill draw — TWO coin draws, up to
///             50 seats in one tx — plus the day seal (the latch rides stage 6 when no ticket leg
///             was priced).
///         Every scenario runs the REAL advanceGame bytecode through the full DeployProtocol
///         wiring (real Game, real CrapsBattle — CrapsViews, a views-only subclass — real
///         Coinflip, real affiliate/quests), so every seat's table-side work is the production
///         path. Every winner is a distinct, never-touched address (cold SSTOREs, no prior
///         seat/claim/stake), and the gas is measured with the call capped at the EIP-7825 limit
///         minus intrinsic, reported INCLUDING the 21,064 intrinsic, and asserted under 16,777,216.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding happens in setUp() — a SEPARATE
///      transaction from the measured body — so the measured call starts on a cold EIP-2929 access
///      list, as a real keeper tx would (the JackpotDayOneWorstCase pattern). The far-future queues
///      [P+1, P+99] are emptied before seeding so the fill walks ONLY distinct fresh wallets (a
///      genesis VAULT/sDGNRS lane would be a refused, cheaper seat). The default scenarios
///      pre-record the day's word; the *WithRngApply* scenarios un-record it so the measured tx
///      also applies the word (coinflip payouts, quest roll, craps openBonusDay, protocol boon draw).
contract PurchaseDailySeeder is DegenerusGame, BucketSeed {
    struct Shape {
        uint24 lvl; // storage `level`; the daily pays purchaseLevel = lvl + 1
        uint256 word; // the day's recorded VRF word
        uint160 base; // disjoint address-space base for synthetic holders
        uint256 mainHolders; // distinct holders per main-board bucket at purchaseLevel (ETH + ticket legs)
        uint256 bonusHolders; // distinct holders per bonus-board bucket at purchaseLevel+1..+4 (unused by
            // the purchase coin draws; kept populated to prove they ignore minted-ahead boards)
        uint256 ffHolders; // distinct holders per far-future queue at purchaseLevel+1..+99 (fill draw)
        uint128 nextPool; // nextPrizePool (> prevPool latches last-purchase; + BAF arm at x0)
        uint128 futurePool; // futurePrizePool: the drip sizes the ETH and ticket legs
        uint256 prevPool; // levelPrizePool[purchaseLevel-1]: sizes the coin budget and the latch target
        uint256 traitHolders; // distinct holders per BONUS-trait bucket at purchaseLevel (level-1 trait draw)
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
        jackpotFlags = 0;
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

        // The empty-board split excludes protocol participation too: genesis deity passes supply
        // virtual bucket entries. A level-1 trait draw excludes them as well — a deity lands on
        // VAULT / sDGNRS, whose seat is refused (cheaper than a fresh seat).
        if (s.bonusHolders == 0 || s.traitHolders != 0) {
            deityBySymbol[VAULT_DEITY_SYMBOL] = address(0);
            deityBySymbol[SDGNRS_DEITY_SYMBOL] = address(0);
        }
        // Level 1: genesis tickets sit in level 1's queues and would be drained (their own stage)
        // ahead of the draws once a fresh word swaps the slots. Empty both slots so the word-apply
        // variant composes the word apply with both draws in ONE tx, as any drained level-1 day does.
        if (s.traitHolders != 0) {
            uint256[] storage q0 = ticketQueue[pl];
            uint256[] storage q1 = ticketQueue[pl | TICKET_SLOT_BIT];
            assembly ("memory-safe") {
                sstore(q0.slot, 0)
                sstore(q1.slot, 0)
            }
        }
        // Empty every unminted queue the fill can walk, then seed only fresh distinct wallets.
        for (uint24 c = pl + 1; c <= pl + 99; ++c) {
            uint256[] storage emptyQueue = ticketQueue[_tqFarFutureKey(c)];
            assembly ("memory-safe") { sstore(emptyQueue.slot, 0) }
        }

        // Keep registry position 0 out of every seeded level (a zero lane index understates gas).
        for (uint24 L = pl; L <= pl + 4; ++L) {
            if (lvlEntryOwner[L].length == 0) lvlEntryOwner[L].push(EntryOwner(address(1), 0));
        }

        for (uint8 q; q < 4; ++q) {
            if (s.mainHolders != 0) {
                _seedBucketDistinct(pl, mainTraits[q], s.mainHolders, s.base + uint160(q) * 0x100000);
            }
            if (s.traitHolders != 0) {
                _seedBucketDistinct(pl, bonusTraits[q], s.traitHolders, s.base + 0x4000000 + uint160(q) * 0x100000);
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
            for (uint24 c = pl + 1; c <= pl + 99; ++c) {
                uint160 b = s.base + 0x2000000 + uint160(c - pl - 1) * 0x1000;
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
    /// @dev Intrinsic cost of a zero-arg advanceGame() tx: 21,000 base + 4 non-zero calldata bytes.
    uint256 internal constant INTRINSIC = 21_064;

    bytes32 internal constant ETH_WIN_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant FAR_WIN_SIG = keccak256("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
    bytes32 internal constant CRAPS_WIN_SIG = keccak256("CoinDrawCrapsWin(address,uint24,bool,bool)");
    bytes32 internal constant BAF_ARMED_SIG = keccak256("BafDrawArmed(uint24)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint16 internal constant PURCHASE_ETH_WINNERS = 49; // 24 + 16 + 8 + 1
    uint16 internal constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;
    uint16 internal constant COIN_DRAW_HALF_SLOTS = 25;

    /// @dev level 109 -> purchaseLevel 110: an x0 (BAF) purchase level at the 0.04 ETH price
    ///      (priceForLevel(109) prices the coin budget), so the target-met latch also arms the BAF draw.
    uint24 internal constant LVL = 109;
    uint160 internal constant BASE = uint160(0x1000000000);
    uint256 internal constant MAIN_HOLDERS = 5000; // per main bucket: ~60 draws each, ~0.4 expected repeats
    uint256 internal constant BONUS_HOLDERS = 200; // minted-ahead boards the purchase draws must ignore
    uint256 internal constant FF_HOLDERS = 8; // per unminted level: 8 distinct wallets (50 fills in <= 7 picks)
    uint256 internal constant L1_TRAIT_HOLDERS = 5000; // per level-1 bonus bucket: ~12 pulls each

    /// @dev Sizing at 0.04 ETH (B = prev * 62.5 FLIP/ETH):
    ///      - future 5000 ETH -> the drip covers 49 ETH winners and >= 120 whole tickets.
    ///      - PREV_POOL        1,000 ETH -> B    62,500: 13 opener seats, 0 days, 25 shares.
    ///      - PREV_POOL_OPEN25 2,080 ETH -> B   130,000: 25 opener seats, 0 days, 25 shares.
    ///      - PREV_POOL_12D    9,920 ETH -> B   620,000: 25 seats, 12 whole days, 25 shares.
    ///      - PREV_POOL_MAX   20,000 ETH -> B 1,250,000: 25 seats, ALL 25 whole days, 25 shares.
    ///      - PREV_POOL_NOSEAT  75.2 ETH -> B     4,700: 0 seats (2,350 < 2,400), 25 shares.
    ///      next = prev + 1 ETH > target -> the last-purchase latch (+ BAF arm at x0).
    uint128 internal constant FUTURE_POOL = 5000 ether;
    uint256 internal constant PREV_POOL = 1000 ether;
    uint256 internal constant PREV_POOL_NOSEAT = 75.2 ether;
    uint256 internal constant PREV_POOL_OPEN25 = 2080 ether;
    uint256 internal constant PREV_POOL_12D = 9920 ether;
    uint256 internal constant PREV_POOL_MAX = 20_000 ether;
    uint128 internal constant NEXT_POOL_LATCH = 1001 ether;
    uint128 internal constant NEXT_POOL_QUIET = 50 ether;
    /// @dev Level 1 (storage level 0, 0.01 ETH): B = prev * 250 -> 5,000 ETH = 1,250,000 FLIP per draw,
    ///      so BOTH draws seat 25 winners for the whole day.
    uint256 internal constant PREV_POOL_L1_MAX = 5000 ether;
    /// @dev Level 1 at 520 ETH: B = 130,000 FLIP per draw -> 25 opener seats each, no upgrades.
    uint256 internal constant PREV_POOL_L1_OPEN25 = 520 ether;

    struct Tally {
        uint8 stage;
        uint256 ethWins;
        uint256 ethDistinct;
        uint256 ticketWins;
        uint256 ticketDistinct;
        uint256 flipWins; // trait-draw coin shares (JackpotFlipWin)
        uint256 farWins; // fill-draw coin shares (FarFutureFlipJackpotWinner)
        uint256 farDistinct;
        uint256 crapsWins; // CoinDrawCrapsWin, every seat attempt
        uint256 crapsDays; // ... of which whole-day seats
        uint256 crapsRefused; // ... of which refused and paid as FLIP
        uint256 crapsLvl1; // ... of which drawn from level 1 (the level-1 trait draw)
        uint256 coinDistinct; // distinct recipients across every coin-draw event (shares + seats)
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

    /// @dev The level-1 day: storage level 0, no main board (no ETH leg at level 1), the trait
    ///      draw's four bonus buckets at level 1 and the fill's queues at 2..100, both draws at B.
    function _shapeLevelOne(uint256 prevPool, bool latch) internal pure returns (PurchaseDailySeeder.Shape memory s) {
        s = _shape(0, 0, FF_HOLDERS, latch ? uint128(prevPool + 1 ether) : NEXT_POOL_QUIET, prevPool);
        s.lvl = 0;
        s.traitHolders = L1_TRAIT_HOLDERS;
    }

    /// @dev One advanceGame tx, called with the EIP-7825 limit less intrinsic (so an over-cap
    ///      composition reverts out of gas rather than passing). `used` INCLUDES the 21,064 intrinsic.
    function _measure() internal returns (uint256 used, Tally memory t) {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        used = g0 - gasleft() + INTRINSIC;

        Vm.Log[] memory logs = vm.getRecordedLogs();
        delete lastLogs;
        for (uint256 i; i < logs.length; ++i) lastLogs.push(logs[i]);
        address[] memory ethW = new address[](PURCHASE_ETH_WINNERS + 8);
        address[] memory tkW = new address[](PURCHASE_PHASE_TICKET_MAX_WINNERS + 8);
        address[] memory farW = new address[](2 * COIN_DRAW_HALF_SLOTS + 8);
        address[] memory coinW = new address[](4 * COIN_DRAW_HALF_SLOTS + 8);
        uint256 coinN;
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
                if (_pushDistinct(coinW, coinN++, w)) ++t.coinDistinct;
                ++t.flipWins;
            } else if (t0 == FAR_WIN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[1])));
                if (_pushDistinct(farW, t.farWins, w)) ++t.farDistinct;
                if (_pushDistinct(coinW, coinN++, w)) ++t.coinDistinct;
                ++t.farWins;
            } else if (t0 == CRAPS_WIN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[1])));
                if (_pushDistinct(coinW, coinN++, w)) ++t.coinDistinct;
                (bool fullDay, bool paidAsFlip) = abi.decode(logs[i].data, (bool, bool));
                ++t.crapsWins;
                if (fullDay) ++t.crapsDays;
                if (paidAsFlip) ++t.crapsRefused;
                if (uint256(logs[i].topics[2]) == 1) ++t.crapsLvl1;
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
        emit log_named_uint("  fill_coin_shares", t.farWins);
        emit log_named_uint("  craps_seats", t.crapsWins);
        emit log_named_uint("  craps_whole_days", t.crapsDays);
        emit log_named_uint("  craps_refused_paid_flip", t.crapsRefused);
        emit log_named_uint("  coin_draw_distinct_recipients", t.coinDistinct);
        emit log_named_uint("  baf_armed", t.bafArmed ? 1 : 0);
    }

    /// @dev Every seat attempt landed (none refused) on a distinct cold wallet, and the fill paid
    ///      its 25 shares to distinct cold wallets disjoint from the seats.
    function _assertFill(Tally memory t, uint256 seats, uint256 days_) internal {
        assertEq(t.flipWins, 0, "the purchase fill uses only the unminted queues");
        assertEq(t.farWins, COIN_DRAW_HALF_SLOTS, "the fill paid all 25 coin shares");
        assertEq(t.crapsWins, seats, "the fill drew every affordable seat");
        assertEq(t.crapsDays, days_, "whole-day upgrades from the front");
        assertEq(t.crapsRefused, 0, "no seat refused: every seat is a real table write");
        assertEq(t.coinDistinct, seats + COIN_DRAW_HALF_SLOTS, "every coin-draw recipient is a distinct cold wallet");
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
        assertEq(tk.ethWins + tk.flipWins + tk.farWins + tk.crapsWins, 0, "only the ticket leg rides the ticket stage");
        assertEq(tk.bafArmed, expectBaf, "the sealing stage latches (and arms the BAF draw) iff the target is met");
        _assertCaps(used);
    }
}

/// @notice The full stage-6 composition at one coin budget: 49 ETH + ticket pricing + the fill at
///         25 cold seats (`_days()` of them whole days) + 25 cold shares; then the ticket stage that
///         pays 120 cold winners and, with the target met, latches + arms the BAF draw.
///         MEASURED: an OPENER seat (vaultComp kind 5 -> a window reservation + slip) costs more than
///         a whole-day seat (deliverPasses -> one day-seat write), so 25 seats with ZERO upgrades
///         (B in [120,000, 160,800) FLIP) is the fill's heaviest budget, not the all-days budget.
abstract contract PurchaseDailyStage is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _days() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public virtual {
        _seed(_shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, uint128(_prev() + 1 ether), _prev()));
    }

    function test_PurchaseDaily_49Eth_TicketPricing_25Seats_25Flip_Measured() public virtual {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("PURCHASE_DAILY (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("PURCHASE_DAILY_STAGE_GAS_", _label()), used);
        _assertStage(t);
        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets + latch + BAF arm", true);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TICKET_STAGE_GAS_", _label()), ticketUsed);
    }

    function _assertStage(Tally memory t) internal {
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "the ETH leg paid all 49 fixed-bucket winners");
        assertEq(t.ethDistinct, PURCHASE_ETH_WINNERS, "all ETH winners are distinct cold addresses");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        _assertFill(t, COIN_DRAW_HALF_SLOTS, _days());
        assertFalse(t.bafArmed, "the latch waits for the sealing ticket stage");
    }
}

/// @notice HEADLINE (heaviest fill budget): 25 cold OPENER seats, no upgrades.
contract PurchaseDailyWorstCase is PurchaseDailyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S25_D00"; }
}

/// @notice 25 seats, 12 upgraded to whole days.
contract PurchaseDailyTwelveDays is PurchaseDailyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_12D; }
    function _days() internal pure override returns (uint256) { return 12; }
    function _label() internal pure override returns (string memory) { return "S25_D12"; }
}

/// @notice The maximum budget: 25 seats, ALL whole days (B >= 1.14M FLIP).
contract PurchaseDailyAllDays is PurchaseDailyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_MAX; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S25_D25"; }
}

/// @notice SPLIT (a): ETH + ticket legs only — the unminted queues are empty (the fill walks 16
///         picks and pays nobody).
contract PurchaseDailyEthTicketsOnly is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, 0, 0, NEXT_POOL_QUIET, PREV_POOL_MAX));
    }

    function test_PurchaseDaily_49Eth_TicketPricing_EmptyFill_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_ETH_TICKETS_ONLY (stage 6): 49 ETH, ticket pricing, empty fill", used, t);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins + t.farWins + t.crapsWins, 0, "the empty fill paid nobody");
        _assertCaps(used);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", false);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_TICKET_STAGE_GAS", ticketUsed);
    }
}

/// @notice The fill-draw LADDER: the main board empty (no ETH, no ticket winners), the fill at a
///         budget per rung. Differences between rungs give the per-seat marginal on the REAL table
///         and the REAL Game (the Game-side extsload vet + the table's seat write + whatever the
///         table reads back from the Game).
abstract contract PurchaseFillRung is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _seats() internal pure virtual returns (uint256);
    function _days() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public {
        _seed(_shape(0, BONUS_HOLDERS, FF_HOLDERS, NEXT_POOL_QUIET, _prev()));
    }

    function test_FillRung_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(_label(), used, t);
        emit log_named_uint(string.concat("FILL_RUNG_GAS_", _label()), used);
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins + t.ticketWins, 0, "empty main board");
        _assertFill(t, _seats(), _days());
        _assertCaps(used);
    }
}

contract PurchaseFillRung00Seats is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_NOSEAT; }
    function _seats() internal pure override returns (uint256) { return 0; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S00_D00"; }
}

contract PurchaseFillRung13Openers is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL; }
    function _seats() internal pure override returns (uint256) { return 13; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S13_D00"; }
}

contract PurchaseFillRung25Openers is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _seats() internal pure override returns (uint256) { return 25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S25_D00"; }
}

contract PurchaseFillRung12Days is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_12D; }
    function _seats() internal pure override returns (uint256) { return 25; }
    function _days() internal pure override returns (uint256) { return 12; }
    function _label() internal pure override returns (string memory) { return "S25_D12"; }
}

contract PurchaseFillRung25Days is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_MAX; }
    function _seats() internal pure override returns (uint256) { return 25; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S25_D25"; }
}

/// @notice TRUE CEILING: the stage-6 composition with the day's word NOT pre-recorded — the measured
///         tx applies the freshly fulfilled VRF word (coinflip payouts, quest roll, craps bonus-day
///         open, protocol boon draw, lootbox finalize) and then pays the whole purchase daily.
abstract contract PurchaseDailyWithRngApplyStage is PurchaseDailyStage, FreshWordLeg {
    function setUp() public override {
        PurchaseDailySeeder.Shape memory s =
            _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, uint128(_prev() + 1 ether), _prev());
        _seedFresh(s);
        _armFreshWord(s.word, 400);
    }

    function test_PurchaseDaily_49Eth_TicketPricing_25Seats_25Flip_Measured() public override {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("PURCHASE_DAILY_WITH_RNG_APPLY (stage 6) ", _label()), used, t);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(lastLogs);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TRUE_CEILING_GAS_", _label()), used);
        _assertStage(t);
        assertGe(cfLogs, 1, "coinflip.processCoinflipPayouts ran in the measured tx");
        assertGe(crLogs, 8, "craps openBonusDay opened the day's 7 windows in the measured tx");
        _assertCaps(used);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets + latch + BAF arm", true);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TRUE_CEILING_TICKET_STAGE_GAS_", _label()), ticketUsed);
    }
}

contract PurchaseDailyWithRngApply is PurchaseDailyWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S25_D00"; }
}

contract PurchaseDailyWithRngApplyAllDays is PurchaseDailyWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_MAX; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S25_D25"; }
}

/// @notice LEVEL 1: the trait draw over level 1 AND the fill over 2..100 in ONE tx, both at 25 cold
///         seats (`_days()` whole days each) + 25 cold shares — 50 seats — plus the day seal and the
///         last-purchase latch (no ticket leg was priced, so the seal rides this stage).
abstract contract PurchaseDailyLevelOneStage is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _days() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public virtual {
        _seed(_shapeLevelOne(_prev(), true));
    }

    function test_LevelOne_TwoDraws_50Seats_50Flip_Latch_Measured() public virtual {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("LEVEL1_TWO_DRAWS (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("LEVEL1_TWO_DRAWS_GAS_", _label()), used);
        _assertLevelOne(t);
        _assertCaps(used);
    }

    function _assertLevelOne(Tally memory t) internal {
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the level-1 purchase daily ran");
        assertEq(t.ethWins + t.ticketWins, 0, "no ETH / ticket leg at level 1");
        assertEq(t.crapsWins, 2 * COIN_DRAW_HALF_SLOTS, "both draws seated 25");
        assertEq(t.crapsLvl1, COIN_DRAW_HALF_SLOTS, "25 seats from the level-1 trait draw");
        assertEq(t.crapsDays, 2 * _days(), "each draw upgraded the expected seats");
        assertEq(t.crapsRefused, 0, "no seat refused");
        assertEq(t.flipWins, COIN_DRAW_HALF_SLOTS, "the trait draw paid 25 shares");
        assertEq(t.farWins, COIN_DRAW_HALF_SLOTS, "the fill paid 25 shares");
        emit log_named_uint("  level1_distinct_recipients_of_100", t.coinDistinct);
        // The trait draw samples with replacement: allow a stray repeat, but the fill is exact.
        assertGe(t.coinDistinct, 98, "all but a stray trait-draw repeat are distinct cold wallets");
        (,, bool lastPurchase,,) = game.purchaseInfo();
        assertTrue(lastPurchase, "the seal latched last purchase day in the same tx");
    }
}

/// @notice Level 1, heaviest budget: 2 x 25 OPENER seats (B = 130,000 FLIP per draw).
contract PurchaseDailyLevelOneTwoDraws is PurchaseDailyLevelOneStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_OPEN25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S50_D00"; }
}

/// @notice Level 1, maximum budget: 2 x 25 whole-day seats (B = 1,250,000 FLIP per draw).
contract PurchaseDailyLevelOneAllDays is PurchaseDailyLevelOneStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S50_D50"; }
}

/// @notice LEVEL 1 TRUE CEILING: the two draws + seal/latch AND the word-apply leg in one tx.
abstract contract PurchaseDailyLevelOneWithRngApplyStage is PurchaseDailyLevelOneStage, FreshWordLeg {
    function setUp() public override {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(_prev(), true);
        _seedFresh(s);
        _armFreshWord(s.word, 400);
    }

    function test_LevelOne_TwoDraws_50Seats_50Flip_Latch_Measured() public override {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("LEVEL1_TWO_DRAWS_WITH_RNG_APPLY (stage 6) ", _label()), used, t);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(lastLogs);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        emit log_named_uint(string.concat("LEVEL1_TWO_DRAWS_TRUE_CEILING_GAS_", _label()), used);
        _assertLevelOne(t);
        assertGe(cfLogs, 1, "coinflip payouts ran in the measured tx");
        assertGe(crLogs, 8, "craps bonus day opened in the measured tx");
        _assertCaps(used);
    }
}

contract PurchaseDailyLevelOneWithRngApply is PurchaseDailyLevelOneWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_OPEN25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S50_D00"; }
}

contract PurchaseDailyLevelOneWithRngApplyAllDays is PurchaseDailyLevelOneWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S50_D50"; }
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
