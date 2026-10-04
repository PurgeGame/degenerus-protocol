// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract EarlyBirdWhaleHarness is DegenerusGameJackpotModule, BucketSeed {
    function price(uint24 target, uint256 budget, uint256 word, bool turbo) external {
        level = target - 1;
        dailyIdx = 100;
        jackpotPhaseFlag = true;
        jackpotCounter = 0;
        jackpotFlags = turbo ? JACKPOT_TURBO : 0;
        rngLockedFlag = true;
        goldenTicket = 0;
        _setCurrentPrizePool(10 ether);
        _setPrizePools(20 ether, uint128((budget * 100 + 2) / 3));
        this.runDailyJackpot(true, level, word, gasleft());
    }

    function seed(uint24 target, uint8 trait, address who, uint256 n) external {
        _seedBucket(target, trait, who, n);
    }
    function seedDistinct(uint24 target, uint8 trait, uint256 n, uint160 base) external {
        _seedBucketDistinct(target, trait, n, base);
    }
    function deity(uint8 trait, address who) external { deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = who; }
    function latch(uint256 entries) external {
        dailyTicketBudgetsPacked = (dailyTicketBudgetsPacked & ((uint256(1) << 144) - 1)) | (entries << 144);
    }
    function packed() external view returns (uint256) { return dailyTicketBudgetsPacked; }
    function pools() external view returns (uint128, uint128) { return _getPrizePools(); }
    function liability() external view returns (uint256) { return claimablePool; }
    function passes(address who) external view returns (uint256) { return whalePassClaims[who]; }
    function unlock() external { rngLockedFlag = false; }
    function creditPasses(address who, uint256 halves) external { whalePassClaims[who] += halves; }
    function owed(uint24 target, address who) external view returns (uint256) {
        uint24 key = target > _mintCeiling() ? _tqFarFutureKey(target) : _tqWriteKey(target);
        return uint32(_entriesOwed(key, who) >> 8);
    }
    function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
        return _pickSoloQuadrant(traits, entropy);
    }
}

contract EarlyBirdWhalePassTest is Test {
    bytes32 private constant PASS = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
    bytes32 private constant TICKET = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    EarlyBirdWhaleHarness private h;
    uint24 private constant TARGET = 10;
    uint256 private constant FULL_PASS = 4.5 ether;

    struct Awards {
        address winner;
        uint256 halves;
        uint256 passEvents;
        uint256 slots;
        uint256 entries;
        bytes32 fingerprint;
        uint256[4] quadrantSlots;
        address[4] passWinners;
        uint256[4] passHalves;
    }

    function setUp() public {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.warp(101 days);
        h = new EarlyBirdWhaleHarness();
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
    }

    /// @dev The day's main board with no hero wagers: the raw roll, then the gold-six daily rule.
    function _traits(uint256 word) private pure returns (uint8[4] memory traits) {
        traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
    }

    function _seed(uint256 word, uint8 active, bool oneWallet) private {
        _seedAt(TARGET, word, active, oneWallet);
    }

    function _seedAt(uint24 target, uint256 word, uint8 active, bool oneWallet) private {
        uint8[4] memory traits = _traits(word);
        for (uint8 q; q < 4; ++q) {
            if (active & (1 << q) != 0) h.seed(target, traits[q], address(uint160(oneWallet ? 0xA000 : 0xA000 + q)), 8);
        }
    }

    function _draw(uint256 word, uint256 entriesEach) private returns (Awards memory a) {
        vm.recordLogs();
        h.runEarlyBirdTickets(word, gasleft());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == PASS) {
                a.winner = address(uint160(uint256(logs[i].topics[1])));
                (uint256 halves, uint8 source) = abi.decode(logs[i].data, (uint256, uint8));
                assertEq(source, 4, "ticket-leg event source");
                a.passWinners[a.passEvents] = a.winner;
                a.passHalves[a.passEvents] = halves;
                a.halves += halves;
                ++a.passEvents;
            } else if (logs[i].topics[0] == TICKET) {
                ++a.quadrantSlots[uint256(logs[i].topics[3]) >> 6];
                (uint32 entries, uint24 source, uint256 index,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
                assertEq(entries, entriesEach, "equal whole-ticket prize per slot");
                a.entries += entries;
                ++a.slots;
                a.fingerprint = keccak256(abi.encode(a.fingerprint, logs[i].topics, source, index));
            }
        }
    }

    /// @dev Whole passes per quadrant: proportional to its ticket winners, rounding passes
    ///      one each in quadrant order.
    function _split(uint256[4] memory slots, uint256 full) private pure returns (uint256[4] memory p) {
        uint256 total = slots[0] + slots[1] + slots[2] + slots[3];
        uint256 left = full;
        for (uint256 q; q < 4; ++q) {
            p[q] = (full * slots[q]) / total;
            left -= p[q];
        }
        for (uint256 q; left != 0; ++q) {
            if (slots[q] == 0) continue;
            ++p[q];
            --left;
        }
    }

    /// @dev One recipient per paying quadrant, drawn from that quadrant's wallets
    ///      (0xA000 + q under `_seed`), each holding its proportional share.
    function _checkPassSplit(Awards memory a) private pure {
        uint256[4] memory want = _split(a.quadrantSlots, a.halves / 2);
        uint256 recipients;
        for (uint256 q; q < 4; ++q) if (want[q] != 0) ++recipients;
        assertEq(a.passEvents, recipients, "one recipient per quadrant holding passes");
        for (uint256 e; e < a.passEvents; ++e) {
            uint256 q = uint160(a.passWinners[e]) - 0xA000;
            assertLt(q, 4, "recipient is a seeded quadrant wallet");
            assertGt(a.quadrantSlots[q], 0, "only quadrants that paid tickets draw a recipient");
            assertEq(a.passHalves[e], want[q] * 2, "proportional share");
        }
    }

    /// @dev Independent doubling reference: 1, doubled at 40, 160, 640, ... ETH, at most `max`.
    function _mult(uint256 value, uint256 max) private pure returns (uint256 m) {
        m = 1;
        uint256 step = 40 ether;
        while (m < max && value >= step) {
            m *= 2;
            step *= 4;
        }
    }

    struct Plan {
        uint256 slots;
        uint256 entries;
        uint256 halves;
    }

    /// @dev Independent ticket-leg model: 96 winners doubled at 40 and 160 ETH of value, at most
    ///      the whole tickets, floored to eight; past 25 tickets each, a surplus
    ///      worth a full pass caps each winner at 25 and converts to whole passes.
    function _model(uint24 target, uint256 budget) private pure returns (Plan memory m) {
        uint256 p = PriceLookupLib.priceForLevel(target);
        uint256 entries = (budget * 4) / p;
        uint256 tickets = entries / 4;
        if (tickets == 0) return m;
        uint256 value = entries * (p / 4);
        uint256 n = 96 * _mult(value, 4);
        if (tickets < n) n = tickets;
        if (n >= 8) n = (n / 8) * 8;
        uint256 each = tickets / n;
        if (each > 25) {
            uint256 full = (value - n * 25 * p) / FULL_PASS;
            if (full != 0) {
                each = 25;
                m.halves = full * 2;
            }
        }
        m.slots = n;
        m.entries = each * 4;
    }

    function _checkPrice(uint24 target, uint256 budget) private {
        h.price(target, budget, 12345, false);
        uint256 p = PriceLookupLib.priceForLevel(target);
        assertEq(uint64(h.packed() >> 144), budget * 4 / p, "pricing latches the whole budget");
        (uint128 next, uint128 future) = h.pools();
        uint256 initialFuture = (budget * 100 + 2) / 3;
        assertEq(future, initialFuture - budget, "full 3% debit stays in next");
        uint256 dailyEntries = uint64(h.packed() >> 8);
        uint256 dailyBudget = uint256(next) - 20 ether - budget;
        assertGe(dailyBudget, dailyEntries * (p / 4));
        assertLt(dailyBudget, (dailyEntries + 1) * (p / 4));
        assertEq(h.liability(), 0, "no cash liability from conversion");
    }

    function _checkSettlement(uint24 target, uint256 budget, uint256 word) private returns (Awards memory a) {
        Plan memory m = _model(target, budget);
        h.price(target, budget, word, false);
        a = _draw(word, m.entries);
        assertEq(a.slots, m.slots, "winner count");
        assertEq(a.halves, m.halves, "surplus passes");
        if (m.halves != 0) _checkPassSplit(a);
    }

    /// @dev For each price tier, the first whole-entry budget whose surplus converts, and one
    ///      wei below it, settle exactly as the model says. Under 2,496 tickets no winner can
    ///      hold more than 25, so the search starts there.
    function test_conversionThresholdsAtEveryPriceTier() public {
        uint256 word = 1337;
        uint24[7] memory targets = [uint24(2), 5, 10, 30, 60, 90, 100];
        for (uint256 i; i < targets.length; ++i) {
            _seedAt(targets[i], word, 15, false);
            uint256 p = PriceLookupLib.priceForLevel(targets[i]);
            uint256 k = 2_496;
            while (_model(targets[i], k * p).halves == 0) ++k;
            uint256 first = (k - 1) * p;
            while (_model(targets[i], first).halves == 0) first += p / 4;
            assertEq(_model(targets[i], first - 1).halves, 0, "one wei below the first conversion");
            uint256 snap = vm.snapshotState();
            _checkSettlement(targets[i], first - 1, word);
            assertTrue(vm.revertToState(snap));
            assertGt(_checkSettlement(targets[i], first, word).halves, 0);
            assertTrue(vm.revertToState(snap));
        }
    }

    function testFuzz_settlementMatchesModel(uint8 tier, uint96 amount) public {
        uint24[7] memory targets = [uint24(2), 5, 10, 30, 60, 90, 100];
        uint24 target = targets[tier % 7];
        uint256 budget = bound(uint256(amount), 0, 2_000 ether);
        _seedAt(target, 1337, 15, false);
        _checkSettlement(target, budget, 1337);
    }

    function testFuzz_exactBudgetAndPoolConservation(uint8 tier, uint96 amount) public {
        uint24[7] memory targets = [uint24(2), 5, 10, 30, 60, 90, 100];
        _checkPrice(targets[tier % 7], bound(uint256(amount), 0, 1_000_000 ether));
    }

    function test_convertedDrawPreservesRecipientsPoolsAndOtherLatches() public {
        uint256 word = 1337;
        _seed(word, 15, false);
        h.price(TARGET, 512 ether, word, false);
        uint256 packed = h.packed();
        (uint128 next, uint128 future) = h.pools();
        uint256 liability = h.liability();
        uint256 snap = vm.snapshotState();
        Awards memory capped = _draw(word, 100);
        assertEq(capped.slots, 384);
        assertEq(capped.passEvents, 3, "one recipient per paying quadrant");
        assertEq(capped.halves, 56);
        _checkPassSplit(capped);
        uint256 credited;
        for (uint256 e; e < 3; ++e) credited += h.passes(capped.passWinners[e]);
        assertEq(credited, 56);
        assertEq(h.packed(), packed & ((uint256(1) << 144) - 1));
        (uint128 nextAfter, uint128 futureAfter) = h.pools();
        assertEq(nextAfter, next);
        assertEq(futureAfter, future);
        assertEq(h.liability(), liability);
        Awards memory replay = _draw(word, 0);
        assertEq(replay.slots + replay.passEvents, 0, "no duplicate settlement");
        assertTrue(vm.revertToState(snap));
        // 384 winners at exactly 25 tickets each: the same draw without a pass surplus.
        h.latch(384 * 25 * 4);
        Awards memory ordinary = _draw(word, 100);
        assertEq(ordinary.fingerprint, capped.fingerprint, "same ticket recipients and source indices");
    }

    function test_duplicateWalletKeepsEveryTicketSlot() public {
        uint256 word = 1337;
        _seed(word, 15, true);
        h.price(TARGET, 512 ether, word, false);
        Awards memory a = _draw(word, 100);
        assertEq(a.slots, 384);
        assertEq(h.owed(TARGET, address(0xA000)), 384 * 100);
        assertEq(a.winner, address(0xA000));
        assertEq(h.passes(a.winner), 56);
    }

    /// @dev Every active-bucket shape: tickets skip the solo quadrant unless it is the only
    ///      active one, and the surplus passes split one recipient per paying quadrant.
    function testFuzz_passesSplitAcrossPayingQuadrants(uint256 word, uint8 mask) public {
        mask &= 15;
        uint8 solo = _soloQuadrant(word);
        _seed(word, mask, false);
        h.price(TARGET, 512 ether, word, false);
        Awards memory a = _draw(word, 100);
        if (mask == 0) {
            assertEq(a.slots + a.passEvents, 0);
            assertEq(uint64(h.packed() >> 144), 0, "empty draw consumes its field");
            return;
        }
        assertEq(a.slots, 384);
        assertEq(a.halves, 56);
        uint8 nonSoloMask = mask & ~uint8(1 << solo);
        for (uint256 q; q < 4; ++q) {
            bool pays = nonSoloMask == 0 ? q == solo : (nonSoloMask & (1 << q)) != 0;
            assertEq(a.quadrantSlots[q] != 0, pays, "tickets land in the eligible quadrants only");
        }
        _checkPassSplit(a);
    }

    /// @dev A quadrant active only through its deity pays tickets and its pass to the deity.
    function test_deityOnlyQuadrantPaysItsDeity() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        uint8 q = solo == 0 ? 1 : 0;
        uint8[4] memory traits = _traits(word);
        _seed(word, uint8(15 ^ (1 << q)), false);
        address deity = address(0xD00D);
        h.deity(traits[q], deity);
        h.price(TARGET, 512 ether, word, false);
        Awards memory a = _draw(word, 100);
        assertGt(a.quadrantSlots[q], 0);
        assertEq(h.owed(TARGET, deity), a.quadrantSlots[q] * 100, "every ticket in the quadrant went to the deity");
        bool found;
        for (uint256 e; e < a.passEvents; ++e) if (a.passWinners[e] == deity) found = true;
        assertTrue(found, "the deity's quadrant draws the deity for its passes");
    }

    function testFuzz_passWinnerIndependentOfAwardAmount(uint256 word) public {
        _seed(word, 15, false);
        h.price(TARGET, 512 ether, word, false);
        Awards memory first = _draw(word, 100);
        h.price(TARGET, 1024 ether, word, false);
        Awards memory second = _draw(word, 100);
        assertEq(first.passEvents, second.passEvents);
        for (uint256 e; e < first.passEvents; ++e) assertEq(first.passWinners[e], second.passWinners[e]);
        assertEq(first.halves, 56);
        assertEq(second.halves, 284);
        assertEq(first.fingerprint, second.fingerprint);
    }

    function testFuzz_freshEntryDrawRetainsRealAndDeityWeights(uint256 word) public {
        uint8 trait = _traits(word)[0];
        h.seedDistinct(TARGET, trait, 64, 0x100000);
        address deity = address(0xD00D);
        h.deity(trait, deity);
        h.price(TARGET, 512 ether, word, false);
        Awards memory a = _draw(word, 100);
        uint256 seed = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(word, uint256(TARGET)))), uint256(0))));
        uint256 root = uint256(keccak256(abi.encode(seed, keccak256("ticket-jackpot-whale"), uint256(100), uint256(TARGET))));
        uint256 virtuals = ((trait >> 3) & 7) >= 5 ? 1 : 2;
        uint256 index = uint256(keccak256(abi.encode(root, uint256(1)))) % (64 + virtuals);
        address expected = index < 64 ? address(uint160(0x100001 + index)) : deity;
        assertEq(a.winner, expected, "fresh entry-weighted sample including virtual deity entries");
        assertEq(a.passEvents, 1);
        assertEq(a.halves, 56);
    }

    // -- solo-quadrant exclusion (main board) ----------------------------------

    /// @dev The ETH leg's own solo-quadrant pick, off the day's main board and the storage
    ///      level (not lvl + 1): the same value runEarlyBirdTickets feeds both the ticket
    ///      draw's exclusion and the surplus whale pass.
    function _soloQuadrant(uint256 word) private view returns (uint8) {
        return h.pickSoloQuadrant(_traits(word), EntropyLib.hash2(word, uint256(TARGET - 1)));
    }

    function test_earlyBirdTicketsNeverLandInTheSoloQuadrantUnlessItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, 15, false);
        h.price(TARGET, 512 ether, word, false);
        vm.recordLogs();
        h.runEarlyBirdTickets(word, gasleft());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != TICKET) continue;
            uint256 q = uint256(logs[i].topics[3]) >> 6;
            assertTrue(q != solo, "early-bird tickets exclude the day's solo ETH quadrant");
            ++n;
        }
        assertGt(n, 0, "tickets were actually drawn");
    }

    function test_earlyBirdTicketsUseTheSoloQuadrantWhenItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, uint8(1 << solo), false);
        h.price(TARGET, 512 ether, word, false);
        vm.recordLogs();
        h.runEarlyBirdTickets(word, gasleft());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != TICKET) continue;
            uint256 q = uint256(logs[i].topics[3]) >> 6;
            assertEq(q, solo, "the only active bucket is the solo quadrant, so it still wins");
            ++n;
        }
        assertGt(n, 0, "tickets were actually drawn from the fallback bucket");
    }

    function test_surplusWhalePassNeverLandsInSoloQuadrantUnlessItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, 15, false);
        h.price(TARGET, 512 ether, word, false);
        Awards memory a = _draw(word, 100);
        assertEq(a.passEvents, 3, "one recipient per paying quadrant");
        for (uint256 e; e < 3; ++e) {
            assertTrue(uint160(a.passWinners[e]) - 0xA000 != solo, "no pass recipient from the solo quadrant");
        }
    }

    function test_surplusWhalePassFallsBackToSoloQuadrantWhenItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, uint8(1 << solo), false);
        h.price(TARGET, 512 ether, word, false);
        Awards memory a = _draw(word, 100);
        assertEq(a.passEvents, 1, "the pass still pays when the solo bucket is the only one active");
        assertEq(a.winner, address(uint160(0xA000 + solo)), "falls back to the solo quadrant");
    }

    function test_turboAndDeferredClaimAggregatesExistingPasses() public {
        uint256 word = 1337;
        _seed(word, 15, false);
        h.price(TARGET, 512 ether, word, true);
        Awards memory a = _draw(word, 100);
        uint256 own = h.passes(a.winner);
        h.creditPasses(a.winner, 2);
        bytes memory original = address(h).code;
        bytes memory whaleCode = address(new DegenerusGameWhaleModule()).code;
        vm.etch(address(h), whaleCode);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.etch(address(h), original);
        assertEq(h.passes(a.winner), own + 2, "blocked claim retains all awards");
        h.unlock();
        vm.etch(address(h), whaleCode);
        vm.warp(132 days);
        vm.expectRevert(bytes4(keccak256("GameOver()")));
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.warp(101 days);
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.expectRevert();
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.etch(address(h), original);
        assertEq(h.passes(a.winner), 0);
        // Each half-pass unit grants one entry at each of 100 levels. Existing
        // immediate tickets at TARGET are separate; inspect the later 99 levels.
        for (uint24 l = TARGET + 1; l < TARGET + 100; ++l) assertEq(h.owed(l, a.winner), own + 2);
    }
}
