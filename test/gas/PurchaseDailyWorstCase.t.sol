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
///             queues [P+1, P+99], walking up to FILL_BATTLE_ENTRANTS = 50 wallets (independent of
///             budget — the walk always tries for 50). Budget B = levelPrizePool[P-1] * 1000 /
///             (price * 400) goes whole to CoinDrawBattle.resolve, which plays every walked wallet
///             as one closed craps battle in the SAME call: two thirds of the budget are stakes (one
///             run per distinct wallet, its bankroll = stakes / units floored to a multiple of 300
///             FLIP, at least 300 or the unit is dropped from the front), one third is the pot. The Game
///             credits what the battle returns in ONE coinflip.creditFlipBatch; CrapsBattle is
///             never touched by the fill anymore — every seat/pass/opener-window concept that used
///             to live here belongs to the trait draw only (see below). All 50 walked wallets play
///             once B >= 22,500 FLIP (stakes >= 15,000, i.e. 50 x the 300-FLIP floor).
///           - LEVEL 1 only (P == 1): no ETH / ticket leg; instead a trait draw over
///             lvlTraitEntry[1] (`payDailyFlipJackpot`, UNCHANGED: craps seats + coin shares) AND
///             the fill draw's battle — plus the day seal (the latch rides stage 6 when no ticket
///             leg was priced).
///         Every scenario runs the REAL advanceGame bytecode through the full DeployProtocol
///         wiring (real Game, real CrapsBattle — CrapsViews, a views-only subclass — real
///         CoinDrawBattle, real Coinflip, real affiliate/quests), so every winner's on-chain work
///         is the production path. Every winner is a distinct, never-touched address (cold
///         SSTOREs, no prior seat/claim/stake), and the gas is measured with the call capped at
///         the EIP-7825 limit minus intrinsic, reported INCLUDING the 21,064 intrinsic, and
///         asserted under 16,777,216.
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
    bytes32 internal constant BATTLE_RUN_SIG =
        keccak256("CoinDrawBattleRun(uint24,address,uint256,uint256,uint256,uint256)");
    bytes32 internal constant BATTLE_POT_SIG = keccak256("CoinDrawBattlePot(uint24,address,uint256)");
    bytes32 internal constant CRAPS_WIN_SIG = keccak256("CoinDrawCrapsWin(address,uint24,bool,bool)");
    bytes32 internal constant BAF_ARMED_SIG = keccak256("BafDrawArmed(uint24)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint16 internal constant PURCHASE_ETH_WINNERS = 49; // 24 + 16 + 8 + 1
    uint16 internal constant PURCHASE_PHASE_TICKET_MAX_WINNERS = 120;
    uint16 internal constant COIN_DRAW_HALF_SLOTS = 25; // trait draw only (unchanged craps split)
    uint256 internal constant FILL_BATTLE_ENTRANTS = 50; // CoinDrawBattle's walked-field cap

    /// @dev level 109 -> purchaseLevel 110: an x0 (BAF) purchase level at the 0.04 ETH price
    ///      (priceForLevel(109) prices the coin budget), so the target-met latch also arms the BAF draw.
    uint24 internal constant LVL = 109;
    uint160 internal constant BASE = uint160(0x1000000000);
    uint256 internal constant MAIN_HOLDERS = 5000; // per main bucket: ~60 draws each, ~0.4 expected repeats
    uint256 internal constant BONUS_HOLDERS = 200; // minted-ahead boards the purchase draws must ignore
    uint256 internal constant FF_HOLDERS = 8; // per unminted level: 8 distinct wallets/level. The
        // walk always tries for FILL_BATTLE_ENTRANTS = 50 regardless of budget (<= 7 picks needed;
        // FUTURE_FLIP_LEVEL_PICKS = 16 gives headroom), so `found` is 50 at every budget below.
    uint256 internal constant L1_TRAIT_HOLDERS = 5000; // per level-1 bonus bucket: ~12 pulls each

    /// @dev Sizing at 0.04 ETH (B = prev * 62.5 FLIP/ETH). CoinDrawBattle plays a run for the
    ///      first `units = min(50, (2B/3) / 300 FLIP)` of the 50 walked wallets (dropped from the
    ///      back when the budget is short), so the fill's run COUNT is a step function of B alone
    ///      — the trait draw's old opener/whole-day split (still real, see COIN_DRAW_HALF_SLOTS)
    ///      has no fill-draw analogue any more:
    ///      - future 5000 ETH -> the drip covers 49 ETH winners and >= 120 whole tickets.
    ///      - PREV_POOL_OPEN25 2,080 ETH -> B 130,000, stakes 86,666 -> units = 50 (saturated: every
    ///        walked wallet plays). THE WORST CASE: heaviest fill budget below the trait draw's
    ///        own tiers, one full 50-row creditFlipBatch.
    ///      - PREV_POOL_NOFILL      1 ETH -> B     62.5, stakes    41.67 -> units = 0: the walk
    ///        still runs (50 wallets found, gas spent), the battle plays nobody, nothing credited.
    ///      - PREV_POOL_PARTIAL   340 ETH -> B 21,250, stakes 14,166 -> units = 47: the entrants
    ///        array is truncated, not every walked wallet gets a run.
    ///      next = prev + 1 ETH > target -> the last-purchase latch (+ BAF arm at x0).
    uint128 internal constant FUTURE_POOL = 5000 ether;
    uint256 internal constant PREV_POOL_OPEN25 = 2080 ether;
    uint256 internal constant PREV_POOL_NOFILL = 1 ether;
    uint256 internal constant PREV_POOL_PARTIAL = 340 ether;
    uint128 internal constant NEXT_POOL_LATCH = 1001 ether;
    uint128 internal constant NEXT_POOL_QUIET = 50 ether;
    /// @dev Level 1 (storage level 0, 0.01 ETH): B = prev * 250. Both draws share this budget, but
    ///      the fill's battle saturates (units = 50) far below the trait draw's own seat/day
    ///      thresholds, so both level-1 tiers below give a full 50-run fill battle; only the trait
    ///      draw's opener/whole-day split still differs between them.
    ///      - PREV_POOL_L1_MAX    5,000 ETH -> B 1,250,000: trait draw seats 25 whole days.
    ///      - PREV_POOL_L1_OPEN25   520 ETH -> B   130,000: trait draw seats 25 openers, no upgrade.
    uint256 internal constant PREV_POOL_L1_MAX = 5000 ether;
    uint256 internal constant PREV_POOL_L1_OPEN25 = 520 ether;

    struct Tally {
        uint8 stage;
        uint256 ethWins;
        uint256 ethDistinct;
        uint256 ticketWins;
        uint256 ticketDistinct;
        uint256 flipWins; // trait-draw coin shares (JackpotFlipWin)
        uint256 battleRuns; // fill-draw battle runs (CoinDrawBattleRun, from COIN_DRAW_BATTLE)
        uint256 battleDistinct;
        uint256 battlePaidTotal; // sum of every run's `paid` field
        uint256 battlePot; // CoinDrawBattlePot's pot, 0 if none minted
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
        address[] memory battleW = new address[](FILL_BATTLE_ENTRANTS + 8);
        address[] memory coinW = new address[](2 * COIN_DRAW_HALF_SLOTS + FILL_BATTLE_ENTRANTS + 8);
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
            } else if (t0 == BATTLE_RUN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[2])));
                if (_pushDistinct(battleW, t.battleRuns, w)) ++t.battleDistinct;
                if (_pushDistinct(coinW, coinN++, w)) ++t.coinDistinct;
                (,, , uint256 paid) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                t.battlePaidTotal += paid;
                ++t.battleRuns;
            } else if (t0 == BATTLE_POT_SIG) {
                address w = address(uint160(uint256(logs[i].topics[2])));
                if (_pushDistinct(coinW, coinN++, w)) ++t.coinDistinct;
                t.battlePot = abi.decode(logs[i].data, (uint256));
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
        emit log_named_uint("  fill_battle_runs", t.battleRuns);
        emit log_named_uint("  fill_battle_paid_total", t.battlePaidTotal);
        emit log_named_uint("  fill_battle_pot", t.battlePot);
        emit log_named_uint("  craps_seats", t.crapsWins);
        emit log_named_uint("  craps_whole_days", t.crapsDays);
        emit log_named_uint("  craps_refused_paid_flip", t.crapsRefused);
        emit log_named_uint("  coin_draw_distinct_recipients", t.coinDistinct);
        emit log_named_uint("  baf_armed", t.bafArmed ? 1 : 0);
    }

    /// @dev The fill draw never touches CrapsBattle: `runs` of the walked field played the battle
    ///      at COIN_DRAW_BATTLE, each a distinct cold wallet, nothing else.
    function _assertFillBattle(Tally memory t, uint256 runs) internal pure {
        assertEq(t.flipWins, 0, "the purchase fill uses only the unminted queues");
        assertEq(t.crapsWins, 0, "the fill draw no longer touches CrapsBattle");
        assertEq(t.battleRuns, runs, "the fill's battle ran the wrong number of entrants");
        assertEq(t.battleDistinct, runs, "every battle run is a distinct cold wallet");
    }

    function _assertCaps(uint256 used) internal {
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }

    /// @dev The fill draw's battle, PROVEN: `resolve` at both caps for all 50 entrants
    ///      (test/craps/CoinDrawBattle.t.sol, 7.31M). The dice in any one measured tx are only
    ///      a sample, so a stage that runs the battle must clear the cap with the WHOLE proven
    ///      bound added on top of what it measured — the measured battle is counted twice,
    ///      which only makes the check stricter.
    uint256 internal constant BATTLE_PROVEN_BOUND = 7_310_000;

    function _assertCapsWithBattle(uint256 used) internal {
        _assertCaps(used);
        emit log_named_uint("  proven_ceiling_with_worst_battle", used + BATTLE_PROVEN_BOUND);
        assertLt(used + BATTLE_PROVEN_BOUND, EIP7825_TX_GAS_CAP, "the worst-case battle could brick this stage");
    }

    /// @dev The priced ticket leg: the next advance, same word, 120 distinct cold winners, sealing the day.
    function _measureTicketStage(string memory label, bool expectBaf) internal returns (uint256 used) {
        Tally memory tk;
        (used, tk) = _measure();
        _emitTally(label, used, tk);
        assertEq(tk.stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage ran");
        assertEq(tk.ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "the ticket stage paid the full 120-winner cap");
        assertEq(tk.ticketDistinct, PURCHASE_PHASE_TICKET_MAX_WINNERS, "all ticket winners are distinct cold addresses");
        assertEq(tk.ethWins + tk.flipWins + tk.battleRuns + tk.crapsWins, 0, "only the ticket leg rides the ticket stage");
        assertEq(tk.bafArmed, expectBaf, "the sealing stage latches (and arms the BAF draw) iff the target is met");
        _assertCaps(used);
    }
}

/// @notice The full stage-6 composition at one coin budget: 49 ETH + ticket pricing + the fill's
///         battle over its 50 walked wallets; then the ticket stage that pays 120 cold winners
///         and, with the target met, latches + arms the BAF draw.
///         MEASURED (HEADLINE): B = PREV_POOL_OPEN25 saturates the battle (all 50 walked wallets
///         play, one 50-row creditFlipBatch) — the old opener-vs-whole-day seat distinction this
///         file used to ladder on on has no fill-draw analogue any more (CrapsBattle is never
///         touched by the fill), so a single saturated-budget scenario is now the fill's worst case.
abstract contract PurchaseDailyStage is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _runs() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public virtual {
        _seed(_shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, uint128(_prev() + 1 ether), _prev()));
    }

    function test_PurchaseDaily_49Eth_TicketPricing_FillBattle_Measured() public virtual {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("PURCHASE_DAILY (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("PURCHASE_DAILY_STAGE_GAS_", _label()), used);
        _assertStage(t);
        _assertCapsWithBattle(used);
        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets + latch + BAF arm", true);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TICKET_STAGE_GAS_", _label()), ticketUsed);
    }

    function _assertStage(Tally memory t) internal {
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "the ETH leg paid all 49 fixed-bucket winners");
        assertEq(t.ethDistinct, PURCHASE_ETH_WINNERS, "all ETH winners are distinct cold addresses");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        _assertFillBattle(t, _runs());
        assertFalse(t.bafArmed, "the latch waits for the sealing ticket stage");
    }
}

/// @notice HEADLINE / WORST CASE: B = PREV_POOL_OPEN25 saturates the fill's battle at all 50
///         walked wallets (one 50-row creditFlipBatch).
contract PurchaseDailyWorstCase is PurchaseDailyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _runs() internal pure override returns (uint256) { return FILL_BATTLE_ENTRANTS; }
    function _label() internal pure override returns (string memory) { return "S50_SATURATED"; }
}

/// @notice SPLIT (a): ETH + ticket legs only — the unminted queues are empty (the fill walks 16
///         picks and pays nobody).
contract PurchaseDailyEthTicketsOnly is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(MAIN_HOLDERS, 0, 0, NEXT_POOL_QUIET, PREV_POOL_OPEN25));
    }

    function test_PurchaseDaily_49Eth_TicketPricing_EmptyFill_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        _emitTally("PURCHASE_DAILY_ETH_TICKETS_ONLY (stage 6): 49 ETH, ticket pricing, empty fill", used, t);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_GAS", used);

        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the purchase-phase daily stage ran");
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS, "49 ETH winners");
        assertEq(t.ticketWins, 0, "the ticket leg waits for its own stage");
        assertEq(t.flipWins + t.battleRuns + t.crapsWins, 0, "the empty fill paid nobody");
        _assertCaps(used);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets", false);
        emit log_named_uint("PURCHASE_DAILY_ETH_TICKET_LEGS_TICKET_STAGE_GAS", ticketUsed);
    }
}

/// @notice The fill-draw LADDER: the main board empty (no ETH, no ticket winners), the fill at a
///         budget per rung. The walk itself always finds FILL_BATTLE_ENTRANTS = 50 wallets
///         regardless of budget; what varies is how many of those 50 the battle affords a run
///         (`units = min(50, (2B/3) / 300 FLIP)`, dropped from the back when short). Three rungs
///         cover the shape: nobody affordable (the walk still runs, the battle plays nobody),
///         partial (units < 50, an entrants-array truncation), and saturated (all 50 play, one
///         50-row creditFlipBatch — same scenario as PurchaseDailyWorstCase's headline).
abstract contract PurchaseFillRung is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _runs() internal pure virtual returns (uint256);
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
        _assertFillBattle(t, _runs());
        _assertCapsWithBattle(used);
    }
}

/// @notice Budget too small to afford even one 50-FLIP-bankroll unit: the walk still finds its 50
///         wallets (gas spent), but CoinDrawBattle.resolve returns empty before any dice run.
contract PurchaseFillRungNoFill is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_NOFILL; }
    function _runs() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "R00_NOFILL"; }
}

/// @notice Budget affords 47 of the 50 walked wallets a run — the entrants-array truncation path.
contract PurchaseFillRungPartial is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_PARTIAL; }
    function _runs() internal pure override returns (uint256) { return 47; }
    function _label() internal pure override returns (string memory) { return "R47_PARTIAL"; }
}

/// @notice Saturated: every one of the 50 walked wallets plays. The same budget tier as
///         PurchaseDailyWorstCase, isolated here from the ETH/ticket legs.
contract PurchaseFillRungSaturated is PurchaseFillRung {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _runs() internal pure override returns (uint256) { return FILL_BATTLE_ENTRANTS; }
    function _label() internal pure override returns (string memory) { return "R50_SATURATED"; }
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

    function test_PurchaseDaily_49Eth_TicketPricing_FillBattle_Measured() public override {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("PURCHASE_DAILY_WITH_RNG_APPLY (stage 6) ", _label()), used, t);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(lastLogs);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TRUE_CEILING_GAS_", _label()), used);
        _assertStage(t);
        assertGe(cfLogs, 1, "coinflip.processCoinflipPayouts ran in the measured tx");
        assertGe(crLogs, 8, "craps openBonusDay opened the day's 7 windows in the measured tx");
        _assertCapsWithBattle(used);

        uint256 ticketUsed = _measureTicketStage("PURCHASE_DAILY_TICKETS (stage 15): 120 tickets + latch + BAF arm", true);
        emit log_named_uint(string.concat("PURCHASE_DAILY_TRUE_CEILING_TICKET_STAGE_GAS_", _label()), ticketUsed);
    }
}

/// @notice TRUE CEILING at the saturated fill budget: the whole word-apply leg plus the headline
///         stage-6 composition, all 50 walked wallets playing the battle.
contract PurchaseDailyWithRngApply is PurchaseDailyWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_OPEN25; }
    function _runs() internal pure override returns (uint256) { return FILL_BATTLE_ENTRANTS; }
    function _label() internal pure override returns (string memory) { return "S50_SATURATED"; }
}

/// @notice LEVEL 1: the trait draw over level 1 (UNCHANGED craps seat/day split) AND the fill's
///         battle over 2..100 in ONE tx, plus the day seal and the last-purchase latch (no ticket
///         leg was priced, so the seal rides this stage). Both draws share `levelPrizePool[0]`,
///         but the fill's battle saturates (50 runs) far below the trait draw's own seat/day
///         thresholds, so at every level-1 tier below the fill plays all 50 walked wallets and
///         only the trait draw's `_days()` differs.
abstract contract PurchaseDailyLevelOneStage is PurchaseDailyFixture {
    function _prev() internal pure virtual returns (uint256);
    function _days() internal pure virtual returns (uint256);
    function _label() internal pure virtual returns (string memory);

    function setUp() public virtual {
        _seed(_shapeLevelOne(_prev(), true));
    }

    function test_LevelOne_TraitDraw25Seats_FillBattle50_Latch_Measured() public virtual {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("LEVEL1_TWO_DRAWS (stage 6) ", _label()), used, t);
        emit log_named_uint(string.concat("LEVEL1_TWO_DRAWS_GAS_", _label()), used);
        _assertLevelOne(t);
        _assertCapsWithBattle(used);
    }

    function _assertLevelOne(Tally memory t) internal {
        assertEq(t.stage, STAGE_PURCHASE_DAILY, "the level-1 purchase daily ran");
        assertEq(t.ethWins + t.ticketWins, 0, "no ETH / ticket leg at level 1");
        // The trait draw's craps half is UNCHANGED; the fill no longer touches CrapsBattle at all,
        // so every craps seat measured here is the trait draw's own.
        assertEq(t.crapsWins, COIN_DRAW_HALF_SLOTS, "the trait draw seated 25");
        assertEq(t.crapsLvl1, COIN_DRAW_HALF_SLOTS, "25 seats from the level-1 trait draw");
        assertEq(t.crapsDays, _days(), "the trait draw upgraded the expected seats");
        assertEq(t.crapsRefused, 0, "no seat refused");
        assertEq(t.flipWins, COIN_DRAW_HALF_SLOTS, "the trait draw paid 25 shares");
        // The fill's battle saturates at every level-1 tier this file uses.
        assertEq(t.battleRuns, FILL_BATTLE_ENTRANTS, "the fill's battle ran fewer than 50 entrants");
        assertEq(t.battleDistinct, FILL_BATTLE_ENTRANTS, "every battle run is a distinct cold wallet");
        emit log_named_uint("  level1_distinct_recipients", t.coinDistinct);
        // The trait draw samples with replacement: allow a stray repeat, but the fill's walk is exact.
        assertGe(
            t.coinDistinct,
            COIN_DRAW_HALF_SLOTS + FILL_BATTLE_ENTRANTS - 1,
            "all but a stray trait-draw repeat are distinct cold wallets"
        );
        (,, bool lastPurchase,,) = game.purchaseInfo();
        assertTrue(lastPurchase, "the seal latched last purchase day in the same tx");
    }
}

/// @notice Level 1, lighter trait-draw budget: 25 OPENER seats (B = 130,000 FLIP), fill saturated.
contract PurchaseDailyLevelOneTwoDraws is PurchaseDailyLevelOneStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_OPEN25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S25_D00_FILL50"; }
}

/// @notice Level 1, maximum budget: 25 whole-day trait-draw seats (B = 1,250,000 FLIP), fill saturated.
contract PurchaseDailyLevelOneAllDays is PurchaseDailyLevelOneStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S25_D25_FILL50"; }
}

/// @notice LEVEL 1 TRUE CEILING: the two draws + seal/latch AND the word-apply leg in one tx.
abstract contract PurchaseDailyLevelOneWithRngApplyStage is PurchaseDailyLevelOneStage, FreshWordLeg {
    function setUp() public override {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(_prev(), true);
        _seedFresh(s);
        _armFreshWord(s.word, 400);
    }

    function test_LevelOne_TraitDraw25Seats_FillBattle50_Latch_Measured() public override {
        (uint256 used, Tally memory t) = _measure();
        _emitTally(string.concat("LEVEL1_TWO_DRAWS_WITH_RNG_APPLY (stage 6) ", _label()), used, t);
        (uint256 cfLogs, uint256 crLogs) = _countLegLogs(lastLogs);
        emit log_named_uint("  coinflip_logs", cfLogs);
        emit log_named_uint("  craps_logs", crLogs);
        emit log_named_uint(string.concat("LEVEL1_TWO_DRAWS_TRUE_CEILING_GAS_", _label()), used);
        _assertLevelOne(t);
        assertGe(cfLogs, 1, "coinflip payouts ran in the measured tx");
        assertGe(crLogs, 8, "craps bonus day opened in the measured tx");
        _assertCapsWithBattle(used);
    }
}

contract PurchaseDailyLevelOneWithRngApply is PurchaseDailyLevelOneWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_OPEN25; }
    function _days() internal pure override returns (uint256) { return 0; }
    function _label() internal pure override returns (string memory) { return "S25_D00_FILL50"; }
}

contract PurchaseDailyLevelOneWithRngApplyAllDays is PurchaseDailyLevelOneWithRngApplyStage {
    function _prev() internal pure override returns (uint256) { return PREV_POOL_L1_MAX; }
    function _days() internal pure override returns (uint256) { return 25; }
    function _label() internal pure override returns (string memory) { return "S25_D25_FILL50"; }
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
