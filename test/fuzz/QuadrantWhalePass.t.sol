// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {GoldenTicketHarness} from "./GoldenTicketArmResolve.t.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {JackpotBoardFixtures} from "./helpers/JackpotBoardFixtures.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract QuadrantWhaleHarness is GoldenTicketHarness {
    function prepare(uint256 current, uint8 counter, bool turbo) external {
        level = 4;
        dailyIdx = 100;
        jackpotCounter = counter;
        jackpotFlags = turbo ? JACKPOT_TURBO : 0;
        jackpotPhaseFlag = true;
        rngLockedFlag = true;
        goldenTicket = 0;
        _setCurrentPrizePool(current);
        _setPrizePools(20 ether, 0);
    }

    function setDeity(uint8 trait, address who) external {
        deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = _seedWallet(who);
    }
    function deityOf(uint8 trait) external view returns (address) {
        return _walletKey(deityBySymbol[(trait >> 6) * 8 + (trait & 7)]);
    }
    function bucketLength(uint8 trait) external view returns (uint256) { return _bucketLength(4, trait); }
    function seedRepeated(uint8 trait, address who) external { _seedBucket(4, trait, who, 65); }
}

contract QuadrantWhalePassTest is Test {
    uint24 private constant LVL = 4;
    uint256 private constant PASS_PRICE = 4.5 ether;
    uint256 private constant UNIT = 0.1 ether;
    uint160 private constant BASE = 0xA00000;
    uint160 private constant DEITY = 0xD00000;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 private constant PASS_WIN = keccak256("JackpotWhalePassWin(uint32,uint256,uint8)");
    QuadrantWhaleHarness private h;

    struct Draw {
        uint256[4] eth;
        uint256[4] each;
        uint256[4] slots;
        uint256[4] halves;
        uint256[4] passEvents;
        address[4] passWinner;
        address[4] ethWinner;
        bytes32 fingerprint;
        uint256 ethTotal;
        uint256 passTotal;
    }

    function setUp() public {
        vm.warp(101 days);
        h = new QuadrantWhaleHarness();
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
    }

    /// @dev The day's main board with no hero wagers: the raw roll, then the gold-six daily rule.
    function _board(uint256 word) private pure returns (uint8[4] memory traits) {
        traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
    }

    function _geometry(uint256 word, uint256 ethBudget, bool finalDay)
        private pure returns (uint8[4] memory traits, uint16[4] memory counts, uint256[4] memory shares, uint256 entropy)
    {
        traits = _board(word);
        entropy = EntropyLib.hash2(word, LVL);
        uint8[4] memory gold;
        uint8 n;
        for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) gold[n++] = q;
        // Gold six takes the solo quadrant before the ordinary gold-quadrant tie-break.
        uint8 solo = traits[3] == GoldSixLib.TRAIT ? 3
            : n == 0 ? uint8((3 - (entropy & 3)) & 3) : gold[(entropy >> 4) % n];
        entropy = (entropy & ~uint256(3)) | uint256((3 - solo) & 3);
        counts = JackpotBucketLib.ethWinnerTargets(ethBudget, entropy);
        uint64 packed = finalDay ? uint64(6000) | (uint64(1333) << 16) | (uint64(1333) << 32) | (uint64(1334) << 48)
            : uint64(2000) * 0x0001000100010001;
        uint16[4] memory bps = JackpotBucketLib.shareBpsByBucket(packed, uint8(entropy & 3));
        shares = JackpotBucketLib.bucketShares(ethBudget, bps, counts, solo);
    }

    struct Expect {
        uint256[4] slots;
        uint256[4] eth;
        uint256[4] full;
    }

    /// @dev Independent payout model: non-solo quadrants pay at most their target in whole
    ///      UNITs after pass conversion; the solo pays its net share plus every active
    ///      non-solo leftover; an empty bucket pays nothing.
    function _expect(uint8[4] memory traits, uint16[4] memory counts, uint256[4] memory shares, uint8 solo)
        private view returns (Expect memory e)
    {
        uint256 leftover;
        bool[4] memory active;
        for (uint8 q; q < 4; ++q) {
            uint8 t = traits[q];
            address deity = t == GoldSixLib.TRAIT ? address(0) : h.deityOf(t);
            active[q] = (h.bucketLength(t) != 0 || deity != address(0)) && shares[q] != 0 && counts[q] != 0;
            if (!active[q] || q == solo) continue;
            uint256 full = shares[q] / (4 * PASS_PRICE);
            uint256 net = shares[q] - full * PASS_PRICE;
            uint256 n = net / UNIT;
            if (n > counts[q]) n = counts[q];
            uint256 each = n == 0 ? 0 : (net / (n * UNIT)) * UNIT;
            if (n != 0) (e.full[q], e.slots[q], e.eth[q]) = (full, n, n * each);
            leftover += net - n * each;
        }
        if (active[solo]) {
            uint256 full = shares[solo] / (4 * PASS_PRICE);
            (e.full[solo], e.slots[solo], e.eth[solo]) = (full, 1, shares[solo] - full * PASS_PRICE + leftover);
        }
    }

    function _seed(uint256 word, uint8 mask, uint256 n) private {
        uint8[4] memory traits = _board(word);
        for (uint8 q; q < 4; ++q) {
            if (mask & (1 << q) != 0) h.seedBucket(LVL, traits[q], n, BASE + uint160(q) * 0x10000);
        }
    }

    function _read(Vm.Log[] memory logs) private view returns (Draw memory d) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == ETH_WIN) {
                uint8 q = uint8(uint256(logs[i].topics[3])) >> 6;
                (uint256 amount, uint256 index) = abi.decode(logs[i].data, (uint256, uint256));
                if (d.slots[q] == 0) d.each[q] = amount;
                assertEq(amount, d.each[q], "every winner in a quadrant gets the same award");
                d.eth[q] += amount;
                d.ethTotal += amount;
                ++d.slots[q];
                d.ethWinner[q] = h.walletKeyOf(uint32(uint256(logs[i].topics[1])));
                d.fingerprint = keccak256(abi.encode(d.fingerprint, logs[i].topics, index));
            } else if (logs[i].topics[0] == PASS_WIN) {
                (uint256 halves, uint8 source) = abi.decode(logs[i].data, (uint256, uint8));
                assertEq(source, 5, "quadrant event source");
                address winner = h.walletKeyOf(uint32(uint256(logs[i].topics[1])));
                uint160 w = uint160(winner);
                uint256 q = w >= DEITY ? w - DEITY : (w - BASE) / 0x10000;
                assertLt(q, 4, "recipient belongs to a quadrant");
                d.passWinner[q] = winner;
                d.halves[q] += halves;
                ++d.passEvents[q];
                d.passTotal += halves;
            }
        }
    }

    function _run(uint256 current, uint256 word, uint8 counter, bool turbo) private returns (Draw memory d) {
        h.prepare(current, counter, turbo);
        bool finalDay = turbo || counter == 2;
        uint256 bps = 10_000;
        if (!finalDay) {
            bps = 600 + uint256(keccak256(abi.encodePacked(word, keccak256("daily-current-bps"), counter))) % 801;
            if (counter != 0) bps *= 2;
        }
        uint256 budget = current * bps / 10_000;
        uint256 tickets = budget / 5;
        uint256 ethBudget = budget - tickets;
        (uint8[4] memory traits, uint16[4] memory counts, uint256[4] memory shares, uint256 entropy) =
            _geometry(word, ethBudget, finalDay);
        uint256 priorLiability = h.claimablePoolView();
        vm.recordLogs();
        h.runDailyJackpot(true, LVL, word, gasleft());
        d = _read(vm.getRecordedLogs());
        uint256 spent;
        uint8 solo = JackpotBucketLib.soloBucketIndex(entropy);
        Expect memory e = _expect(traits, counts, shares, solo);
        for (uint8 q; q < 4; ++q) {
            uint256 len = h.bucketLength(traits[q]);
            // Gold six has no virtual deity entry.
            address deity = traits[q] == GoldSixLib.TRAIT ? address(0) : h.deityOf(traits[q]);
            uint256 full = e.full[q];
            uint256 cost = full * PASS_PRICE;
            assertEq(d.halves[q], full * 2, "whole passes from this quadrant's quarter");
            assertEq(d.passEvents[q], full == 0 ? 0 : 1, "one recipient per qualifying quadrant");
            assertEq(d.slots[q], e.slots[q], "ETH winner count");
            assertEq(d.eth[q], e.eth[q], "ETH paid, with leftovers on the solo");
            if (q != solo && d.slots[q] != 0) {
                assertLe(d.slots[q], counts[q], "never above the target");
                assertGe(d.each[q], UNIT, "at least one unit per award");
                assertEq(d.each[q] % UNIT, 0, "whole units");
            }
            if (full != 0) {
                assertGe(h.whalePassOf(d.passWinner[q]), full * 2, "pass claim credited");
                uint256 root = uint256(keccak256(abi.encode(
                    EntropyLib.hash2(entropy, q), keccak256("jackpot-quadrant-whale"), uint256(100), uint256(LVL)
                )));
                uint8 color = (traits[q] >> 3) & 7;
                uint256 virtuals = deity == address(0) ? 0 : color >= 5 ? 1 : 2;
                uint256 index = uint256(keccak256(abi.encode(root, uint256(1)))) % (len + virtuals);
                address expected = index < len ? address(BASE + uint160(q) * 0x10000 + uint160(index) + 1) : deity;
                assertEq(d.passWinner[q], expected, "fresh entry draw with real and deity weights");
            }
            spent += cost;
        }
        (uint128 next, uint128 future) = h.poolsView();
        assertEq(next, 20 ether + tickets, "only the normal daily ticket budget reaches next");
        uint256 paid = d.ethTotal + spent;
        assertLe(paid, ethBudget);
        assertEq(future, spent + (finalDay ? ethBudget - paid : 0), "pass backing and final-day unpaid ETH go to future");
        assertEq(h.currentPoolView(), finalDay ? 0 : current - tickets - paid, "current debit counts pass backing exactly once");
        assertEq(h.claimablePoolView() - priorLiability, d.ethTotal, "only ETH awards create cash liability");
        assertEq(h.currentPoolView() + uint256(next) + uint256(future) + d.ethTotal, current + 20 ether, "pool conservation");
    }

    function testFuzz_allDayShapesMasksAndAccounting(uint96 amount, uint256 word, uint8 shape, uint8 mask) public {
        shape %= 4;
        _seed(word, mask & 15, 65);
        _run(bound(uint256(amount), 5 ether, 1_000_000 ether), word, shape == 3 ? 0 : shape, shape == 3);
    }

    function test_goldSixSoloPriorityCounterexampleReplay() public {
        uint256 word = 641518955479923548691900238103279543832;
        uint8[4] memory traits = _board(word);
        assertEq(traits[3], GoldSixLib.TRAIT, "replay includes a surviving gold six");
        (,,, uint256 entropy) = _geometry(word, 100_000 ether, false);
        assertEq(JackpotBucketLib.soloBucketIndex(entropy), 3, "gold six owns the solo draw");
        testFuzz_allDayShapesMasksAndAccounting(506806022868, word, 9, 46);
    }

    function test_thresholdsAndRemainderAtOneWeiBoundaries() public {
        uint256 word = 1337;
        _seed(word, 15, 65);
        uint256[6] memory targets = [uint256(9 ether), 18 ether - 1, 18 ether, 18 ether + 1, 20 ether, 36 ether];
        for (uint256 i; i < targets.length; ++i) {
            uint256 ethBudget = targets[i];
            uint8 solo;
            bool found;
            for (uint256 step; step < 128; ++step) {
                (, , uint256[4] memory shares, uint256 entropy) = _geometry(word, ethBudget, true);
                solo = JackpotBucketLib.soloBucketIndex(entropy);
                if (shares[solo] == targets[i]) { found = true; break; }
                ethBudget = targets[i] + ethBudget - shares[solo];
            }
            assertTrue(found, "fixture reaches exact quadrant boundary");
            Draw memory d = _run(ethBudget * 5 / 4, word, 0, true);
            uint256 full = targets[i] / 18 ether;
            assertEq(d.halves[solo], full * 2);
            assertGe(d.eth[solo], targets[i] - full * PASS_PRICE, "sub-pass remainder stays with ETH winner");
        }
    }

    function testFuzz_awardSizeDoesNotRerollEitherDraw(uint256 word) public {
        _seed(word, 15, 65);
        Draw memory a = _run(1250 ether, word, 0, true);
        Draw memory b = _run(2500 ether, word, 0, true);
        assertEq(a.fingerprint, b.fingerprint, "ETH source indices and recipients unchanged");
        for (uint8 q; q < 4; ++q) {
            assertEq(a.passWinner[q], b.passWinner[q], "pass recipient independent of amount");
            assertGt(b.halves[q], a.halves[q]);
            assertEq(h.whalePassOf(a.passWinner[q]), a.halves[q] + b.halves[q], "claim aggregation");
        }
    }

    /// @dev A normal jackpot day at about 42 ETH (no quarter reaches 18 ETH) and at three times
    ///      that (every quarter converts) share the 40 ETH winner targets, so conversion must
    ///      leave the ETH draw unchanged.
    function test_originalEthDrawMatchesUnconvertedDraw() public {
        uint256 word = 1337;
        _seed(word, 15, 512);
        uint256 bps = 2 * (600 + uint256(keccak256(abi.encodePacked(word, keccak256("daily-current-bps"), uint8(1)))) % 801);
        uint256 current = 52.5 ether * 10_000 / bps;
        uint256 snap = vm.snapshotState();
        Draw memory ordinary = _run(current, word, 1, false);
        assertEq(ordinary.passTotal, 0, "no quarter reaches a whole pass");
        assertTrue(vm.revertToState(snap));
        Draw memory converted = _run(3 * current, word, 1, false);
        for (uint8 q; q < 4; ++q) assertGt(converted.halves[q], 0, "every quarter converts");
        bool fresh;
        for (uint8 q; q < 4; ++q) if (h.claimableOf(converted.passWinner[q]) == 0) fresh = true;
        assertTrue(fresh, "a pass recipient need not be an ETH winner");
        assertEq(converted.fingerprint, ordinary.fingerprint, "conversion preserves the original ETH draw");
    }

    function test_deityOnlyBucketsReceiveWholePasses() public {
        uint256 word = 1337;
        uint8[4] memory traits = _board(word);
        for (uint8 q; q < 4; ++q) h.setDeity(traits[q], address(DEITY + q));
        Draw memory d = _run(1250 ether, word, 0, true);
        for (uint8 q; q < 4; ++q) assertEq(d.passWinner[q], address(DEITY + q));
    }

    function testFuzz_realAndVirtualEntriesKeepTheirWeights(uint256 word) public {
        _seed(word, 15, 65);
        uint8[4] memory traits = _board(word);
        for (uint8 q; q < 4; ++q) h.setDeity(traits[q], address(DEITY + q));
        _run(1250 ether, word, 0, true);
    }

    function test_goldenTicketStillArmsOnSoloEthWinner() public {
        uint256 word = JackpotBoardFixtures.wordFor([7, 7, 7, 7], [1, 2, 3, 4], false);
        _seed(word, 15, 512);
        Draw memory d = _run(1250 ether, word, 0, true);
        (,,, uint256 entropy) = _geometry(word, 1000 ether, true);
        uint8 solo = JackpotBucketLib.soloBucketIndex(entropy);
        assertEq(h.walletKeyOf(uint32(h.goldenTicketRaw())), d.ethWinner[solo]);
        assertTrue(d.ethWinner[solo] != d.passWinner[solo], "separate draws exercise distinct winners");
    }

    function test_oneWalletCanWinPassesFromMultipleQuadrants() public {
        uint256 word = 1337;
        uint8[4] memory traits = _board(word);
        address player = address(BASE + 1);
        for (uint8 q; q < 4; ++q) h.seedRepeated(traits[q], player);
        h.prepare(1250 ether, 0, true);
        vm.recordLogs();
        h.runDailyJackpot(true, LVL, word, gasleft());
        Draw memory d = _read(vm.getRecordedLogs());
        assertEq(d.passEvents[0], 4, "four awards without wallet deduplication");
        assertEq(h.whalePassOf(player), d.passTotal);
        assertEq(h.claimableOf(player), d.ethTotal);
        // A 1,000 ETH final-day budget targets 256 + 128 + 32 winners plus the solo.
        assertEq(d.slots[0] + d.slots[1] + d.slots[2] + d.slots[3], 417);
    }
}
