// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title GoldRushHarness -- drives the live payDailyJackpot arm/resolve surface
/// @notice Extends the production DegenerusGameJackpotModule so the inherited external
///         `payDailyJackpot` executes the live gold-rush arm/resolve path in THIS
///         contract's storage. Adds only storage seeders and read-only views; overrides
///         NO production logic.
/// @dev Test-only. NO contracts/*.sol is mutated; this harness lives entirely under test/.
contract GoldRushHarness is DegenerusGameJackpotModule {
    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        address[] storage holders = lvlTraitEntry[lvl][traitId];
        for (uint256 i; i < count; ++i) {
            holders.push(address(base + uint160(i + 1)));
        }
    }

    function setLevel(uint24 v) external {
        level = v;
    }

    function setJackpotCounter(uint8 v) external {
        jackpotCounter = v;
    }

    function setDailyIdx(uint24 v) external {
        dailyIdx = v;
    }

    function setCurrentPool(uint256 v) external {
        _setCurrentPrizePool(v);
    }

    function setPools(uint128 nextBal, uint128 futBal) external {
        _setPrizePools(nextBal, futBal);
    }

    function setGoldRushRaw(uint256 v) external {
        goldRush = v;
    }

    function setPending(uint128 nextPending, uint128 futPending) external {
        prizePoolPendingPacked = (uint256(futPending) << 128) | nextPending;
    }

    function setYieldAcc(uint256 v) external {
        yieldAccumulator = v;
    }

    /// @dev Wager `amount` units on (quadrant, symbol) for the hero pool read by
    ///      draws whose frozen dailyIdx == day.
    function setHeroWager(uint24 day, uint8 q, uint8 s, uint32 amount) external {
        dailyHeroWagers[day][q] |= uint256(amount) << (uint256(s) * 32);
    }

    function goldRushRaw() external view returns (uint256) {
        return goldRush;
    }

    function claimableOf(address who) external view returns (uint256) {
        return _claimableOf(who);
    }

    function whalePassOf(address who) external view returns (uint256) {
        return whalePassClaims[who];
    }

    function claimablePoolView() external view returns (uint256) {
        return uint256(claimablePool);
    }

    function currentPoolView() external view returns (uint256) {
        return _getCurrentPrizePool();
    }

    function poolsView() external view returns (uint128 nextBal, uint128 futBal) {
        (nextBal, futBal) = _getPrizePools();
    }
}

/// @dev Recorder etched at ContractAddresses.COINFLIP: captures creditFlip calls.
contract CoinflipRecorder {
    address public lastPlayer;
    uint256 public lastAmount;
    uint256 public calls;

    function creditFlip(address p, uint256 a) external {
        lastPlayer = p;
        lastAmount = a;
        ++calls;
    }

    fallback() external payable {
        assembly {
            mstore(0, 0)
            return(0, 32)
        }
    }
}

/// @dev Recorder etched at ContractAddresses.WWXRP: captures mintPrize calls.
contract WwxrpRecorder {
    address public lastTo;
    uint256 public lastAmount;
    uint256 public calls;

    function mintPrize(address to, uint256 a) external {
        lastTo = to;
        lastAmount = a;
        ++calls;
    }

    fallback() external payable {
        assembly {
            mstore(0, 0)
            return(0, 32)
        }
    }
}

/// @dev Zero-returning sink for incidental external reads (stETH etc.).
contract ReturnZeroSink {
    fallback() external payable {
        assembly {
            mstore(0, 0)
            return(0, 32)
        }
    }
}

/// @title GoldRushArmResolve -- cross-day gold-rush arm/resolve/ban proofs
/// @notice Locks the drafted mechanic:
///         - a 4-gold main board arms the solo bucket winner (slot fields + event)
///         - non-4-gold and same-idx draws neither arm nor resolve
///         - the next draw (any dailyIdx gap) resolves by ITS gold count: every ladder
///           rung pays the ruled amounts (WWXRP / passes / fp percents / flip credit)
///         - grand = 4 golds + armed-quadrant symbol repeat; headline remainder split
///         - the hero is banned from the armed quadrant on the resolve draw (armed rule)
///           and on same-idx re-rolls after resolution (prevBan rule)
///         - resolution rewrites the slot exactly once (no double fire); a chain arm
///           preserves the resolve-day ban fields
contract GoldRushArmResolve is Test {
    GoldRushHarness internal h;
    CoinflipRecorder internal flipRec;
    WwxrpRecorder internal wwxrpRec;

    uint24 internal constant LVL = 5;
    uint24 internal constant ARM_IDX = 10;
    uint256 internal constant CUR_POOL = 1000 ether;
    uint128 internal constant NEXT_POOL = 200 ether;
    uint128 internal constant FUT_POOL = 1000 ether;
    uint256 internal constant HALF_PASS = 2.25 ether;
    uint256 internal constant COIN_UNIT = 1000 ether;

    event GoldRushArmed(
        address indexed winner,
        uint24 indexed level,
        uint8 quadrant,
        uint8 symbol
    );

    event GoldRushWin(
        address indexed winner,
        uint24 indexed level,
        uint8 bonusGolds,
        bool grand,
        uint256 ethAmount,
        uint256 halfPassCount,
        uint256 flipCredit,
        uint256 wwxrpAmount
    );

    function setUp() public {
        h = new GoldRushHarness();

        CoinflipRecorder fr = new CoinflipRecorder();
        vm.etch(ContractAddresses.COINFLIP, address(fr).code);
        flipRec = CoinflipRecorder(payable(ContractAddresses.COINFLIP));

        WwxrpRecorder wr = new WwxrpRecorder();
        vm.etch(ContractAddresses.WWXRP, address(wr).code);
        wwxrpRec = WwxrpRecorder(payable(ContractAddresses.WWXRP));

        ReturnZeroSink sink = new ReturnZeroSink();
        vm.etch(ContractAddresses.STETH_TOKEN, address(sink).code);
        vm.etch(ContractAddresses.JACKPOTS, address(sink).code);

        h.setLevel(LVL);
        h.setJackpotCounter(1); // day 2: no early-bird, not final
        h.setDailyIdx(ARM_IDX);
        h.setCurrentPool(CUR_POOL);
        h.setPools(NEXT_POOL, FUT_POOL);
    }

    // -- board crafting -------------------------------------------------------

    /// @dev Builds a VRF word whose base board has the given per-quadrant colors and
    ///      symbols (bits [6i+5:6i+3] = color, [6i+2:6i] = symbol). `salt` fills the
    ///      unrelated high bits.
    function wordFor(
        uint8[4] memory colors,
        uint8[4] memory syms,
        uint256 salt
    ) internal pure returns (uint256 w) {
        for (uint256 i; i < 4; ++i) {
            w |= (uint256(colors[i]) << 3 | uint256(syms[i])) << (i * 6);
        }
        w |= salt << 24;
    }

    function allGoldWord(uint8[4] memory syms, uint256 salt) internal pure returns (uint256) {
        return wordFor([7, 7, 7, 7], syms, salt);
    }

    /// @dev Trait byte for quadrant i on a board word: 64*i + 6-bit group.
    function traitOf(uint256 word, uint8 i) internal pure returns (uint8) {
        return uint8(uint256(i) * 64 + ((word >> (uint256(i) * 6)) & 0x3F));
    }

    function seedBoardBuckets(uint256 word, uint160 base) internal {
        for (uint8 i; i < 4; ++i) {
            h.seedBucket(LVL, traitOf(word, i), 5, base + uint160(i) * 100);
        }
    }

    // -- flows ----------------------------------------------------------------

    /// @dev Runs an arm day at ARM_IDX with an all-gold board and returns the armed
    ///      winner/quadrant/symbol read back from the slot.
    function armDay(
        uint8[4] memory syms
    ) internal returns (address winner, uint8 quadrant, uint8 symbol, uint256 word) {
        word = allGoldWord(syms, 0xA11CE);
        seedBoardBuckets(word, 0x1000);
        h.payDailyJackpot(true, LVL, word);

        uint256 g = h.goldRushRaw();
        assertEq((g >> 189) & 1, 1, "armed flag set");
        winner = address(uint160(g));
        quadrant = uint8((g >> 160) & 3);
        symbol = uint8((g >> 162) & 7);
        assertEq(uint256(uint24((g >> 165) & 0xFFFFFF)), ARM_IDX, "armedIdx == arm draw idx");
        assertEq(symbol, syms[quadrant], "armed symbol == official solo symbol");
        assertTrue(winner != address(0), "armed winner nonzero");
    }

    /// @dev Runs a resolve draw at `idx` with `word`, returning the GoldRushWin payload.
    function resolveDay(
        uint24 idx,
        uint256 word
    )
        internal
        returns (uint8 golds, bool grand, uint256 eth, uint256 passes, uint256 flip, uint256 wwxrp)
    {
        h.setDailyIdx(idx);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256(
            "GoldRushWin(address,uint24,uint8,bool,uint256,uint256,uint256,uint256)"
        );
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                found = true;
                (golds, grand, eth, passes, flip, wwxrp) = abi.decode(
                    logs[i].data,
                    (uint8, bool, uint256, uint256, uint256, uint256)
                );
            }
        }
        assertTrue(found, "GoldRushWin emitted");
    }

    function officialMainBoard(Vm.Log[] memory logs) internal pure returns (uint32 mainPacked) {
        bytes32 topic = keccak256("DailyWinningTraits(uint24,uint32,uint32,uint24)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                (mainPacked, , ) = abi.decode(logs[i].data, (uint32, uint32, uint24));
            }
        }
    }

    // -- arm ------------------------------------------------------------------

    function testArmSetsSlotAndEmits() public {
        vm.recordLogs();
        (address winner, uint8 quadrant, uint8 symbol, ) = armDay([1, 2, 3, 4]);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("GoldRushArmed(address,uint24,uint8,uint8)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), winner, "event winner");
                (uint8 q, uint8 s) = abi.decode(logs[i].data, (uint8, uint8));
                assertEq(q, quadrant, "event quadrant");
                assertEq(s, symbol, "event symbol");
            }
        }
        assertTrue(found, "GoldRushArmed emitted");
    }

    function testNoArmWithoutFourGolds() public {
        uint256 word = wordFor([7, 7, 7, 6], [1, 2, 3, 4], 0xA11CE);
        seedBoardBuckets(word, 0x1000);
        h.payDailyJackpot(true, LVL, word);
        assertEq(h.goldRushRaw(), 0, "3 golds never arms");
    }

    function testNoArmOnPurchasePhase() public {
        uint256 word = allGoldWord([1, 2, 3, 4], 0xA11CE);
        seedBoardBuckets(word, 0x1000);
        h.payDailyJackpot(false, LVL, word);
        assertEq(h.goldRushRaw(), 0, "purchase phase never arms (no solo bucket)");
    }

    // -- resolve gating -------------------------------------------------------

    function testNoResolveOnSameIdx() public {
        (address winner, , , ) = armDay([1, 2, 3, 4]);
        uint256 gBefore = h.goldRushRaw();
        // Same frozen idx (a re-run of the arm draw's index) must not resolve.
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, allGoldWord([1, 2, 3, 4], 0xBEEF));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256(
            "GoldRushWin(address,uint24,uint8,bool,uint256,uint256,uint256,uint256)"
        );
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != topic, "no GoldRushWin at armedIdx");
        }
        // Same-day re-arm overwrites with identical armedIdx; winner may differ but
        // the armed flag and idx are unchanged.
        uint256 gAfter = h.goldRushRaw();
        assertEq((gAfter >> 189) & 1, 1, "still armed");
        assertEq((gAfter >> 165) & 0xFFFFFF, (gBefore >> 165) & 0xFFFFFF, "armedIdx unchanged");
        assertTrue(winner != address(0));
    }

    function testResolveAfterIdxGap() public {
        (address winner, , , ) = armDay([1, 2, 3, 4]);
        // Gap of 3 draws (stall / skipped payDailyJackpot day) still resolves.
        (uint8 golds, bool grand, , , , ) = resolveDay(
            ARM_IDX + 3,
            wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D)
        );
        assertEq(golds, 0, "0 golds on resolve board");
        assertFalse(grand);
        assertEq(wwxrpRec.lastTo(), winner, "wwxrp consolation to armed winner");
    }

    function testNoDoubleFire() public {
        armDay([1, 2, 3, 4]);
        resolveDay(ARM_IDX + 1, wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D));
        // Next draw: armed flag is gone, nothing fires.
        h.setDailyIdx(ARM_IDX + 2);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xFEED));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256(
            "GoldRushWin(address,uint24,uint8,bool,uint256,uint256,uint256,uint256)"
        );
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != topic, "resolution fires exactly once");
        }
    }

    // -- ladder rungs ---------------------------------------------------------

    function testRungZeroGolds() public {
        (address winner, , , ) = armDay([1, 2, 3, 4]);
        uint256 claimBefore = h.claimableOf(winner);
        uint256 passBefore = h.whalePassOf(winner);
        (uint8 golds, bool grand, uint256 eth, uint256 passes, uint256 flip, uint256 wwxrp) =
            resolveDay(ARM_IDX + 1, wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D));
        assertEq(golds, 0);
        assertFalse(grand);
        assertEq(eth, 0);
        assertEq(passes, 0);
        assertEq(flip, 0);
        assertEq(wwxrp, 100 ether, "0 golds = 100 WWXRP");
        assertEq(wwxrpRec.calls(), 1);
        assertEq(wwxrpRec.lastTo(), winner);
        assertEq(wwxrpRec.lastAmount(), 100 ether);
        assertEq(h.claimableOf(winner), claimBefore, "no ETH leg");
        assertEq(h.whalePassOf(winner), passBefore, "no pass leg");
    }

    function testRungOneGold() public {
        (address winner, , , ) = armDay([1, 2, 3, 4]);
        uint256 passBefore = h.whalePassOf(winner);
        (uint8 golds, , uint256 eth, uint256 passes, uint256 flip, uint256 wwxrp) =
            resolveDay(ARM_IDX + 1, wordFor([7, 1, 2, 3], [5, 5, 5, 5], 0xD00D));
        assertEq(golds, 1);
        assertEq(eth, 0);
        assertEq(passes, 2, "1 gold = one whole pass = 2 half-passes");
        assertEq(flip, 0);
        assertEq(wwxrp, 0);
        assertEq(h.whalePassOf(winner) - passBefore, 2);
    }

    function testRungTwoGolds() public {
        (address winner, , , ) = armDay([1, 2, 3, 4]);
        uint256 claimBefore = h.claimableOf(winner);
        uint256 passBefore = h.whalePassOf(winner);
        (, uint128 futBefore) = h.poolsView();
        uint256 poolBefore = h.claimablePoolView();
        (uint8 golds, , uint256 eth, uint256 passes, , ) =
            resolveDay(ARM_IDX + 1, wordFor([7, 7, 2, 3], [5, 5, 5, 5], 0xD00D));
        assertEq(golds, 2);
        uint256 expEth = uint256(futBefore) / 50;
        assertEq(eth, expEth, "2 golds = 2% of futurePrizePool");
        assertEq(passes, expEth / HALF_PASS, "equal value in half-passes, rounded down");
        assertEq(h.claimableOf(winner) - claimBefore, expEth, "ETH credited claimable");
        assertEq(h.whalePassOf(winner) - passBefore, passes);
        assertEq(h.claimablePoolView() - poolBefore, expEth, "liability tracks ETH leg only");
    }

    function testRungThreeGolds() public {
        armDay([1, 2, 3, 4]);
        (, uint128 futBefore) = h.poolsView();
        (uint8 golds, , uint256 eth, uint256 passes, , ) =
            resolveDay(ARM_IDX + 1, wordFor([7, 7, 7, 3], [5, 5, 5, 5], 0xD00D));
        assertEq(golds, 3);
        assertEq(eth, uint256(futBefore) / 20, "3 golds = 5% of futurePrizePool");
        assertEq(passes, eth / HALF_PASS);
    }

    function testRungFourGoldsNoMatch() public {
        (address winner, , uint8 symbol, ) = armDay([1, 2, 3, 4]);
        (, uint128 futBefore) = h.poolsView();
        // All-gold resolve board whose symbols all differ from the armed symbol.
        uint8 miss = (symbol + 1) & 7;
        (uint8 golds, bool grand, uint256 eth, uint256 passes, uint256 flip, ) =
            resolveDay(ARM_IDX + 1, allGoldWord([miss, miss, miss, miss], 0xD00D));
        assertEq(golds, 4);
        assertFalse(grand, "symbol miss = no grand");
        uint256 expEth = uint256(futBefore) / 10;
        assertEq(eth, expEth, "4 golds = 10% of futurePrizePool");
        assertEq(passes, (2 * expEth) / HALF_PASS, "double the ETH leg in passes");
        uint256 expFlipValue = uint256(futBefore) / 20;
        uint256 expFlip = (expFlipValue * COIN_UNIT) / PriceLookupLib.priceForLevel(LVL + 1);
        assertEq(flip, expFlip, "5% fp as flip credit at ticket rate");
        assertEq(flipRec.calls(), 1);
        assertEq(flipRec.lastPlayer(), winner);
        assertEq(flipRec.lastAmount(), expFlip);
    }

    function testGrand() public {
        (address winner, , uint8 symbol, ) = armDay([1, 2, 3, 4]);
        // Zero the current pool so the resolve draw's normal daily distribution
        // pays nothing: the all-gold grand board necessarily shares the armed
        // quadrant's trait with a seeded arm-day bucket, and a daily win there
        // would pollute the winner's claimable delta.
        h.setCurrentPool(0);
        uint256 claimBefore = h.claimableOf(winner);
        // The yield accumulator (advance-written only) counts toward the
        // headline; the pending accumulators and claimable do not — both move
        // with player actions inside the RNG window.
        h.setPending(3 ether, 5 ether);
        h.setYieldAcc(7 ether);
        (uint128 nextBefore, uint128 futBefore) = h.poolsView();
        uint256 headline = uint256(nextBefore) + uint256(futBefore) + 7 ether;
        // All-gold board repeating the armed symbol in every quadrant: the armed
        // quadrant matches whichever quadrant was stored.
        (uint8 golds, bool grand, uint256 eth, uint256 passes, uint256 flip, uint256 wwxrp) =
            resolveDay(ARM_IDX + 1, allGoldWord([symbol, symbol, symbol, symbol], 0xD00D));
        assertEq(golds, 4);
        assertTrue(grand, "4 golds + symbol repeat = grand");
        uint256 expEth = uint256(futBefore) / 4;
        assertEq(eth, expEth, "grand ETH leg = 25% of futurePrizePool");
        uint256 remainder = headline - expEth;
        uint256 passValue = (remainder * 3) / 4;
        assertEq(passes, passValue / HALF_PASS, "75% of remainder in half-passes");
        uint256 expFlip = ((remainder - passValue) * COIN_UNIT) /
            PriceLookupLib.priceForLevel(LVL + 1);
        assertEq(flip, expFlip, "25% of remainder as flip credit");
        assertEq(wwxrp, 0);
        assertEq(h.claimableOf(winner) - claimBefore, expEth, "only ETH leg hits claimable");
        (, uint128 futAfterRaw) = h.poolsView();
        // The 0.5% carryover slice runs after the resolve debit in the same call.
        uint256 futAfterResolve = uint256(futBefore) - expEth;
        assertEq(
            uint256(futAfterRaw),
            futAfterResolve - futAfterResolve / 200,
            "future pool: grand debit then daily carve"
        );
    }

    // -- hero ban -------------------------------------------------------------

    function testHeroBannedFromArmedQuadrantOnResolveDay() public {
        (, uint8 quadrant, , ) = armDay([1, 2, 3, 4]);
        // Whale the resolve-day hero pool onto the armed quadrant with a symbol
        // that would flip the grand match.
        h.setHeroWager(ARM_IDX + 1, quadrant, 6, type(uint32).max);
        uint256 word = wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D);
        h.setDailyIdx(ARM_IDX + 1);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32 mainPacked = officialMainBoard(logs);
        uint8[4] memory official = JackpotBucketLib.unpackWinningTraits(mainPacked);
        // Sole wagered slot was banned -> pool empty -> no hero anywhere: the
        // armed quadrant keeps its base symbol on the official board.
        assertEq(official[quadrant] & 7, 5, "armed quadrant keeps base symbol");
        for (uint8 i; i < 4; ++i) {
            assertEq(official[i], traitOf(word, i), "board is the pure base roll");
        }
    }

    function testHeroStillLandsElsewhereOnResolveDay() public {
        (, uint8 quadrant, , ) = armDay([1, 2, 3, 4]);
        uint8 other = (quadrant + 1) & 3;
        h.setHeroWager(ARM_IDX + 1, quadrant, 6, type(uint32).max);
        h.setHeroWager(ARM_IDX + 1, other, 2, 1000);
        uint256 word = wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D);
        h.setDailyIdx(ARM_IDX + 1);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        uint8[4] memory official = JackpotBucketLib.unpackWinningTraits(
            officialMainBoard(vm.getRecordedLogs())
        );
        assertEq(official[quadrant] & 7, 5, "armed quadrant still base");
        assertEq(official[other] & 7, 2, "hero lands on the unbanned quadrant");
    }

    function testPrevBanRuleBansAfterResolution() public {
        // Slot in resolved state only: prevBan flag, quadrant 2, idx == current.
        uint24 idx = 42;
        h.setDailyIdx(idx);
        h.setGoldRushRaw(
            (uint256(1) << 190) | (uint256(2) << 191) | (uint256(idx) << 193)
        );
        h.setHeroWager(idx, 2, 6, type(uint32).max);
        uint256 word = wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 winTopic = keccak256(
            "GoldRushWin(address,uint24,uint8,bool,uint256,uint256,uint256,uint256)"
        );
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != winTopic, "prevBan-only state never pays");
        }
        uint8[4] memory official = JackpotBucketLib.unpackWinningTraits(
            officialMainBoard(logs)
        );
        assertEq(official[2] & 7, 5, "prevBan keeps hero off quadrant on same idx");
    }

    function testPrevBanExpiresNextIdx() public {
        uint24 idx = 42;
        h.setDailyIdx(idx + 1);
        h.setGoldRushRaw(
            (uint256(1) << 190) | (uint256(2) << 191) | (uint256(idx) << 193)
        );
        h.setHeroWager(idx + 1, 2, 6, type(uint32).max);
        uint256 word = wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        uint8[4] memory official = JackpotBucketLib.unpackWinningTraits(
            officialMainBoard(vm.getRecordedLogs())
        );
        assertEq(official[2] & 7, 6, "stale prevBan does not ban the next draw");
    }

    // -- slot lifecycle -------------------------------------------------------

    function testResolutionWritesPrevBan() public {
        (, uint8 quadrant, , ) = armDay([1, 2, 3, 4]);
        resolveDay(ARM_IDX + 1, wordFor([0, 1, 2, 3], [5, 5, 5, 5], 0xD00D));
        uint256 g = h.goldRushRaw();
        assertEq((g >> 189) & 1, 0, "armed cleared");
        assertEq((g >> 190) & 1, 1, "prevBan flag set");
        assertEq((g >> 191) & 3, quadrant, "prevBan quadrant = armed quadrant");
        assertEq((g >> 193) & 0xFFFFFF, ARM_IDX + 1, "prevBan idx = resolve idx");
    }

    function testChainArmPreservesPrevBan() public {
        (, uint8 oldQuadrant, uint8 symbol, ) = armDay([1, 2, 3, 4]);
        // Resolve board is itself all-gold (symbols miss the grand) with seeded
        // buckets: resolves the old rush AND arms a new one in the same draw.
        uint8 miss = (symbol + 1) & 7;
        uint256 word = allGoldWord([miss, miss, miss, miss], 0xD00D);
        seedBoardBuckets(word, 0x9000);
        h.setDailyIdx(ARM_IDX + 1);
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 winTopic = keccak256(
            "GoldRushWin(address,uint24,uint8,bool,uint256,uint256,uint256,uint256)"
        );
        bytes32 armTopic = keccak256("GoldRushArmed(address,uint24,uint8,uint8)");
        bool sawWin;
        bool sawArm;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == winTopic) sawWin = true;
            if (logs[i].topics[0] == armTopic) sawArm = true;
        }
        assertTrue(sawWin, "chain draw resolves the old rush");
        assertTrue(sawArm, "chain draw arms a new rush");
        uint256 g = h.goldRushRaw();
        assertEq((g >> 189) & 1, 1, "new armed flag");
        assertEq((g >> 165) & 0xFFFFFF, ARM_IDX + 1, "new armedIdx = chain draw idx");
        assertEq((g >> 190) & 1, 1, "prevBan preserved through chain arm");
        assertEq((g >> 191) & 3, oldQuadrant, "prevBan quadrant is the OLD quadrant");
        assertEq((g >> 193) & 0xFFFFFF, ARM_IDX + 1, "prevBan pinned to chain draw idx");
    }
}
