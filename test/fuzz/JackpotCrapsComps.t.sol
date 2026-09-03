// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev Extends the production module so `payDailyFlipJackpot` runs the live
///      `_runFlipJackpot -> _awardDailyCoinToTraitWinners / _awardDailyCoinWithCrapsComp`
///      path in this contract's own storage. Seeders and mirror views only — NO production
///      logic is overridden.
contract JackpotCompHarness is DegenerusGameJackpotModule, BucketSeed {
    function seedBudgetFor(uint24 lvl, uint256 coinBudget) external {
        // Mirror of `_calcDailyCoinBudget` solved for the pool. priceForLevel(level)=0.01 ether
        // at level 1 makes the map exact for budgets divisible by 250 wei.
        levelPrizePool[lvl - 1] = (coinBudget * PriceLookupLib.priceForLevel(level) * 400) / PRICE_COIN_UNIT;
    }

    function coinBudgetOf(uint24 lvl) external view returns (uint256) {
        return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(level) * 400);
    }

    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        _seedBucketDistinct(lvl, traitId, count, base);
    }

    /// @dev Every one of the 256 possible trait bytes gets `count` distinct holders, so any
    ///      trait the day rolls finds a nonempty bucket and every pull resolves a winner.
    function seedAllTraits(uint24 lvl, uint256 count) external {
        for (uint256 t; t < 256; ++t) {
            for (uint256 i; i < count; ++i) {
                _seedBucket(lvl, uint8(t), address(uint160((t << 32) | (i + 1))), 1);
            }
        }
    }

    function clearBucket(uint24 lvl, uint8 traitId) external {
        _seedBucketClear(lvl, traitId);
    }

    function bucketAt(uint24 lvl, uint8 traitId, uint256 idx) external view returns (address) {
        return _bucketOwnerAt(lvl, traitId, idx);
    }

    function bucketLen(uint24 lvl, uint8 traitId) external view returns (uint256) {
        return lvlTraitEntry[lvl][traitId].length;
    }

    function seedFarQueue(uint24 lvl, uint256 count, uint160 base) external {
        address[] storage q = ticketQueue[_tqFarFutureKey(lvl)];
        for (uint256 i; i < count; ++i) {
            q.push(address(base + uint160(i + 1)));
        }
    }

    function passValue() external pure returns (uint256) {
        return NORMAL_DAY_PASS_VALUE;
    }
}

/// @dev Records every FLIP credit that crosses the boundary, batch or single.
contract CompCoinflipDouble {
    address[] public players;
    uint256[] public amounts;
    uint256 public batches;
    uint256 public total;
    bool public revertAll;

    function setRevertAll(bool r) external {
        revertAll = r;
    }

    function creditFlipBatch(address[] calldata p, uint256[] calldata a) external {
        require(!revertAll, "coinflip-wiring-broken");
        for (uint256 i; i < p.length; ++i) {
            if (p[i] != address(0) && a[i] != 0) {
                players.push(p[i]);
                amounts.push(a[i]);
                total += a[i];
            }
        }
        ++batches;
    }

    function creditFlip(address p, uint256 a) external {
        players.push(p);
        amounts.push(a);
        total += a;
    }

    function count() external view returns (uint256) {
        return players.length;
    }
}

/// @dev The craps credit door's double: banks up to a configurable per-player capacity and
///      returns the ACTUAL credited counts, exactly as the shipped `creditPasses` does.
contract CompCrapsDouble {
    uint256 public capacity = type(uint32).max;
    bool public revertAll;
    mapping(address => uint256) public normals;
    uint256 public calls;
    uint256 public totalCredited;

    function setCapacity(uint256 c) external {
        capacity = c;
    }

    function setRevertAll(bool r) external {
        revertAll = r;
    }

    function creditPasses(address player, uint32 normal, uint32 high)
        external
        returns (uint32 normalCredited)
    {
        require(!revertAll, "craps-wiring-broken");
        require(high == 0, "the comp lane must never send highs");
        ++calls;
        uint256 held = normals[player];
        uint256 space = capacity > held ? capacity - held : 0;
        uint256 got = normal;
        if (got > space) got = space;
        normals[player] = held + got;
        totalCredited += got;
        normalCredited = uint32(got);
    }
}

/// @title JackpotCrapsComps — the coin jackpot's comp-quadrant branch, proven on the live module
/// @notice One VRF-chosen quadrant of the near-future daily FLIP jackpot pays whole normal Craps
///         day comps when its nominal quarter funds at least one; every funded whole comp is
///         spread across at most six existing ticket-weighted winner slots, and everything not
///         actually banked as a comp stays in the other three quadrants' FLIP leg. Below the
///         threshold the shipped path runs byte-for-byte unchanged.
contract JackpotCrapsCompsTest is Test {
    JackpotCompHarness internal h;
    CompCoinflipDouble internal coinflip;
    CompCrapsDouble internal craps;

    uint24 internal constant LVL = 1;
    uint256 internal constant WORD = uint256(keccak256("comp-word"));
    uint256 internal P; // NORMAL_DAY_PASS_VALUE
    uint256 internal constant UNIT = 100 ether;

    bytes32 internal constant FLIP_WIN_SIG =
        keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant COMP_WIN_SIG =
        keccak256("JackpotCrapsCompWin(address,uint24,uint8,uint32,uint256)");
    bytes32 internal constant FAR_WIN_SIG =
        keccak256("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
    bytes32 internal constant COMP_TAG = keccak256("coin-craps-comp");
    bytes32 internal constant LEVEL_TAG = keccak256("coin-level");

    function setUp() public {
        h = new JackpotCompHarness();
        P = h.passValue();
        vm.etch(ContractAddresses.COINFLIP, address(new CompCoinflipDouble()).code);
        vm.etch(ContractAddresses.CRAPS, address(new CompCrapsDouble()).code);
        coinflip = CompCoinflipDouble(ContractAddresses.COINFLIP);
        craps = CompCrapsDouble(ContractAddresses.CRAPS);
        craps.setCapacity(type(uint32).max);
    }

    // ── Fixture helpers ─────────────────────────────────────────────────────

    /// @dev Seed a coin budget whose NEAR leg (75%, far rounded down first) is exactly `near`.
    ///      `near` must be a multiple of 750 so `coinBudget = near * 4 / 3` stays a whole
    ///      multiple of the 250-wei pool granularity.
    function _seedNear(uint256 near) internal {
        uint256 coinBudget = (near * 4) / 3;
        h.seedBudgetFor(LVL, coinBudget);
        assertEq(h.coinBudgetOf(LVL), coinBudget, "the pool seed did not round-trip the budget");
        assertEq(coinBudget - (coinBudget * 2500) / 10_000, near, "the near leg is not the requested figure");
    }

    function _run() internal returns (Vm.Log[] memory logs) {
        vm.recordLogs();
        h.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        logs = vm.getRecordedLogs();
    }

    function _compQuadrant() internal pure returns (uint256) {
        return _compQuadrantOf(WORD);
    }

    function _compQuadrantOf(uint256 word) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(word, COMP_TAG))) & 3;
    }

    /// @dev The scheduled pull count of quadrant `q` under the 50-index `i % 4` rotation.
    function _pullsOf(uint256 q) internal pure returns (uint256) {
        return (50 - q + 3) / 4;
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    /// @dev The comp events' traits all share one quadrant; return it (reverts if none logged).
    function _compTraitOf(Vm.Log[] memory logs) internal pure returns (uint8 trait) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == COMP_WIN_SIG) return uint8(uint256(logs[i].topics[3]));
        }
        revert("no comp event");
    }

    // ── The threshold ───────────────────────────────────────────────────────

    /// @dev BELOW the boundary the shipped path runs unchanged: fifty scheduled pulls across
    ///      all four quadrants, one equal whole-100-FLIP amount, no comp event, no Craps call —
    ///      and the winner set replays exactly from the published level/holder hashes.
    function test_belowTheThresholdTheOldPathRunsUntouched() public {
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * P - 750); // one pool granule under the boundary
        Vm.Log[] memory logs = _run();

        assertEq(_countSig(logs, COMP_WIN_SIG), 0, "a sub-threshold budget entered comp mode");
        assertEq(craps.calls(), 0, "a sub-threshold budget called Craps");
        assertEq(_countSig(logs, FLIP_WIN_SIG), 50, "the fifty scheduled pulls did not all pay");

        // Every amount is the same whole-100-FLIP figure the old rule computes.
        uint256 near = 4 * P - 750;
        uint256 expected = ((near / UNIT) / 50) * UNIT;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, expected, "a below-threshold pull paid off the equal share");
        }
        assertEq(coinflip.batches(), 1, "the fifty pulls did not land as one batch");
    }

    /// @dev AT the boundary exactly one quadrant converts: one comp slot, one Craps call, no
    ///      FLIP from the comp trait, and the other quadrants' pulls all pay one equal share of
    ///      what the comp did not spend.
    function test_atTheThresholdOneQuadrantPaysOneComp() public {
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * P);
        Vm.Log[] memory logs = _run();

        assertEq(_countSig(logs, COMP_WIN_SIG), 1, "Q == P did not fund exactly one comp");
        assertEq(craps.calls(), 1, "one comp slot did not make exactly one Craps call");
        assertEq(craps.totalCredited(), 1, "the one comp did not bank one pass");

        uint256 q = _compQuadrant();
        uint8 compTrait = _compTraitOf(logs);
        assertEq(uint256(compTrait >> 6), q, "the comp trait is not the chosen quadrant's");

        uint256 flips = _countSig(logs, FLIP_WIN_SIG);
        assertEq(flips, 50 - _pullsOf(q), "the other quadrants did not keep their scheduled pulls");
        uint256 expected = (((4 * P - P) / UNIT) / (50 - _pullsOf(q))) * UNIT;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
            assertTrue(uint8(uint256(logs[i].topics[3]) >> 6) != q, "the comp quadrant also took FLIP");
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, expected, "a non-comp pull paid off the equal share");
        }
    }

    /// @dev EVERY QUADRANT CAN GO COMP, and the FLIP denominator follows it: 37 scheduled
    ///      non-comp pulls where quadrant 0 or 1 converted, 38 where 2 or 3 did. One vector per
    ///      quadrant, found by walking candidate words through the same mirror the contract runs.
    function test_everyQuadrantVectorsWithItsOwnDenominator() public {
        h.seedAllTraits(LVL, 8);
        uint256 snap = vm.snapshotState();
        bool[4] memory seen;
        uint256 covered;
        for (uint256 n; covered < 4 && n < 64; ++n) {
            uint256 word = uint256(keccak256(abi.encode("quadrant-vector", n)));
            uint256 q = _compQuadrantOf(word);
            if (seen[q]) continue;
            seen[q] = true;
            ++covered;

            vm.revertToState(snap);
            snap = vm.snapshotState();
            _seedNear(4 * 2 * P);
            vm.recordLogs();
            h.payDailyFlipJackpot(LVL, word, LVL, LVL);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            uint256 pulls = 50 - _pullsOf(q);
            assertEq(pulls, 37 + (q >> 1), "the scheduled non-comp pull count is not 37/38 by quadrant");
            assertEq(_countSig(logs, FLIP_WIN_SIG), pulls, "a quadrant's FLIP pulls do not match its denominator");
            uint256 expected = (((4 * 2 * P - 2 * P) / UNIT) / pulls) * UNIT;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] == FLIP_WIN_SIG) {
                    assertTrue(uint8(uint256(logs[i].topics[3]) >> 6) != q, "the comp quadrant took FLIP");
                    (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                    assertEq(amount, expected, "the equal share does not divide by this quadrant's pulls");
                } else if (logs[i].topics[0] == COMP_WIN_SIG) {
                    assertEq(uint256(uint8(uint256(logs[i].topics[3])) >> 6), q, "a comp event left its quadrant");
                }
            }
        }
        assertEq(covered, 4, "the word walk did not reach all four quadrants");
    }

    // ── Spreading whole comps ───────────────────────────────────────────────

    /// @dev Slot boundaries: every funded whole comp is issued, at most six slots, counts
    ///      differing by at most one before saturation.
    function test_everyFundedCompIsSpreadAcrossAtMostSixSlots() public {
        uint8[7] memory fundables = [1, 5, 6, 7, 11, 12, 13];
        h.seedAllTraits(LVL, 8);
        // `vm.etch` shares the doubles' storage across cases, so each case runs from a state
        // snapshot instead of a re-etch.
        uint256 snap = vm.snapshotState();
        for (uint256 c; c < fundables.length; ++c) {
            uint256 f = fundables[c];
            vm.revertToState(snap);
            snap = vm.snapshotState();
            _seedNear(4 * f * P);
            Vm.Log[] memory logs = _run();

            uint256 slots = f < 6 ? f : 6;
            assertEq(_countSig(logs, COMP_WIN_SIG), slots, "the slot count is not min(fundable, 6)");
            assertEq(craps.totalCredited(), f, "the funded whole comps were not all issued");

            uint256 lo = type(uint256).max;
            uint256 hi;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != COMP_WIN_SIG) continue;
                (uint32 n,) = abi.decode(logs[i].data, (uint32, uint256));
                if (n < lo) lo = n;
                if (n > hi) hi = n;
            }
            assertLe(hi - lo, 1, "comp slot counts differ by more than one");
        }
    }

    /// @dev A thin quadrant redistributes: with ONE nonempty cell, that one wallet takes every
    ///      funded comp — and duplicate slots to one wallet are the ordinary jackpot semantics.
    function test_aThinQuadrantConcentratesAllCompsOnTheSlotsFound() public {
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * 7 * P); // seven fundable comps
        // Learn the day's comp trait with a dry run off a snapshot, so the dry run's credits
        // and events leave no residue in the world the claim is graded on.
        uint256 snap = vm.snapshotState();
        Vm.Log[] memory dry = _run();
        uint8 compTrait = _compTraitOf(dry);
        vm.revertToState(snap);

        h.clearBucket(LVL, compTrait);
        h.seedBucket(LVL, compTrait, 1, 0xFACE0000);
        Vm.Log[] memory logs = _run();

        // Range is one level, so every one of the quadrant's pulls samples the same bucket and
        // the same single holder: six slots found, all the same wallet, seven comps among them.
        assertEq(_countSig(logs, COMP_WIN_SIG), 6, "one holder did not fill all six slots");
        address winner = h.bucketAt(LVL, compTrait, 0);
        assertEq(craps.normals(winner), 7, "the single wallet did not take every funded comp");
    }

    /// @dev An EMPTY comp quadrant banks nothing and its whole nominal budget pays out as FLIP
    ///      to the other quadrants.
    function test_anEmptyCompQuadrantReturnsItsWholeBudgetToFlip() public {
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * 3 * P);
        uint256 snap = vm.snapshotState();
        Vm.Log[] memory dry = _run();
        uint8 compTrait = _compTraitOf(dry);
        vm.revertToState(snap);

        h.clearBucket(LVL, compTrait);
        Vm.Log[] memory logs = _run();

        assertEq(_countSig(logs, COMP_WIN_SIG), 0, "an empty quadrant still banked comps");
        assertEq(craps.totalCredited(), 0, "an empty quadrant still credited passes");
        uint256 q = _compQuadrant();
        uint256 expected = (((4 * 3 * P) / UNIT) / (50 - _pullsOf(q))) * UNIT;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, expected, "the unspent quadrant budget did not reach the FLIP shares");
        }
    }

    /// @dev SATURATION cannot delete value: what the lane refuses stays in the FLIP budget, and
    ///      comp events carry only the actually banked counts.
    function test_aSaturatedLaneKeepsRefusedValueInFlip() public {
        h.seedAllTraits(LVL, 8);
        craps.setCapacity(1); // each wallet's lane holds one pass and refuses the rest
        _seedNear(4 * 12 * P); // twelve fundable comps over six slots of two
        Vm.Log[] memory logs = _run();

        uint256 banked = craps.totalCredited();
        assertLe(banked, 6, "six one-pass lanes banked more than six");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != COMP_WIN_SIG) continue;
            (uint32 n,) = abi.decode(logs[i].data, (uint32, uint256));
            assertEq(n, 1, "a comp event carried more than the lane banked");
        }
        uint256 q = _compQuadrant();
        uint256 expected = ((((4 * 12 * P) - banked * P) / UNIT) / (50 - _pullsOf(q))) * UNIT;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, expected, "the refused pass value did not return to the FLIP shares");
        }
    }

    // ── Selection parity, conservation, determinism ─────────────────────────

    /// @dev The other quadrants' winners replay exactly from the published hashes: the branch
    ///      changed WHO gets what, never how anyone is drawn.
    function test_nonCompSelectionReplaysFromThePublishedHashes() public {
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * 5 * P);
        Vm.Log[] memory logs = _run();

        uint256 q = _compQuadrant();
        // Recover the day's four winning traits from the emitted events (trait >> 6 is the
        // quadrant, and range-one seeding guarantees every scheduled pull emitted).
        uint8[4] memory traits;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 sig = logs[i].topics[0];
            if (sig != FLIP_WIN_SIG && sig != COMP_WIN_SIG) continue;
            uint8 t = uint8(uint256(logs[i].topics[3]));
            traits[t >> 6] = t;
        }

        uint256 cursor;
        for (uint256 i; i < 50; ++i) {
            if (i % 4 == q) continue;
            uint8 trait = traits[i % 4];
            // range == 1 collapses the level hash to LVL; the holder hash is the live rule.
            uint256 idx = uint256(keccak256(abi.encode(WORD, trait, uint24(LVL), i))) % h.bucketLen(LVL, trait);
            address expected = h.bucketAt(LVL, trait, idx);
            // The i-th non-comp pull is the cursor-th FLIP log.
            uint256 seen;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics[0] != FLIP_WIN_SIG) continue;
                if (seen++ == cursor) {
                    assertEq(
                        address(uint160(uint256(logs[j].topics[1]))),
                        expected,
                        "a non-comp pull drew someone the published hashes do not name"
                    );
                    break;
                }
            }
            ++cursor;
        }
    }

    /// @dev Conservation across fuzzed budgets: actually banked comp value plus actually
    ///      credited FLIP never exceeds the near budget, in or out of comp mode.
    function test_fuzz_compAndFlipConserveTheNearBudget(uint256 nearSeed) public {
        uint256 near = (bound(nearSeed, UNIT, 40 * P) / 750) * 750;
        if (near == 0) near = 750;
        h.seedAllTraits(LVL, 8);
        _seedNear(near);
        _run();
        assertLe(
            craps.totalCredited() * P + coinflip.total(),
            near,
            "comp value plus FLIP credits exceeded the near budget"
        );
    }

    /// @dev Same state, same word: identical quadrant, slots, counts and FLIP winners.
    function test_theDrawReplaysDeterministically() public {
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * 7 * P);
        Vm.Log[] memory a = _run();

        setUp();
        h.seedAllTraits(LVL, 8);
        _seedNear(4 * 7 * P);
        Vm.Log[] memory b = _run();

        assertEq(a.length, b.length, "two identical draws logged different counts");
        for (uint256 i; i < a.length; ++i) {
            assertEq(
                keccak256(abi.encode(a[i].topics)),
                keccak256(abi.encode(b[i].topics)),
                "two identical draws diverged in winner, level or trait"
            );
            assertEq(keccak256(a[i].data), keccak256(b[i].data), "two identical draws diverged in figures");
        }
    }

    /// @dev The far-future leg is untouched by comp mode: its winners come from the queue it
    ///      has always drawn from and its equal shares spend only its own 25%.
    function test_theFarFutureLegIsIsolated() public {
        h.seedAllTraits(LVL, 8);
        // The sampler draws ten levels from [lvl+5, lvl+99]; seed them all so every pull finds
        // a queue and the ten far winners land deterministically.
        for (uint24 d = 5; d < 100; ++d) {
            h.seedFarQueue(LVL + d, 3, 0xBEEF0000);
        }
        _seedNear(4 * 5 * P);
        Vm.Log[] memory logs = _run();

        uint256 farBudget = ((4 * 5 * P * 4) / 3) - 4 * 5 * P; // coinBudget - near
        uint256 farPaid;
        uint256 farCount = _countSig(logs, FAR_WIN_SIG);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FAR_WIN_SIG) continue;
            uint256 amount = abi.decode(logs[i].data, (uint256));
            farPaid += amount;
            address w = address(uint160(uint256(logs[i].topics[1])));
            assertEq(uint160(w) & 0xFFFF0000, uint160(0xBEEF0000), "a far winner came from outside the queue");
        }
        assertEq(farCount, 10, "ten fully seeded samples did not pay ten far winners");
        assertLe(farPaid, farBudget, "the far leg spent more than its own quarter");
        assertEq(farPaid, ((farBudget / UNIT) / 10) * UNIT * 10, "the far shares are not the equal split");
    }

    /// @dev The production module must keep real deployment headroom — the same 24,400-byte
    ///      rail the repo holds CrapsBattle to, well under EIP-170's 24,576.
    function test_productionJackpotModuleRuntimeFitsTheRail() public {
        DegenerusGameJackpotModule production = new DegenerusGameJackpotModule();
        emit log_named_uint("DegenerusGameJackpotModule runtime bytes", address(production).code.length);
        assertLe(address(production).code.length, 24_400, "the jackpot module left too little deployment headroom");
    }

    /// @dev A DOWNSTREAM Coinflip revert rolls the whole draw back atomically: the pass
    ///      credits already banked in the same transaction unwind with it, so a comp can never
    ///      outlive the FLIP leg it was carved out of.
    function test_aRevertedCoinflipBatchRollsBackThePassCredits() public {
        h.seedAllTraits(LVL, 8);
        coinflip.setRevertAll(true);
        _seedNear(4 * 3 * P);
        vm.expectRevert(bytes("coinflip-wiring-broken"));
        h.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        assertEq(craps.totalCredited(), 0, "a reverted draw left pass credits behind");
        assertEq(craps.calls(), 0, "a reverted draw left the Craps call count behind");
    }

    /// @dev THE REAL DOOR. The shipped CrapsBattle — its `OnlyGame` gate, packed-lane credit
    ///      and `CrapsPassesCredited` log included — etched at its pinned address, and the
    ///      module at the GAME's own address: exactly the caller identity a delegatecall gives
    ///      it in production. The comps bank as real packed credits that the real contract
    ///      reads back, and a caller that is not the Game is refused by the real gate.
    function test_theRealCrapsBattleBanksTheCompsForTheGame() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsViews()).code);
        vm.etch(ContractAddresses.GAME, address(new JackpotCompHarness()).code);
        JackpotCompHarness g = JackpotCompHarness(ContractAddresses.GAME);
        g.seedAllTraits(LVL, 8);
        g.seedBudgetFor(LVL, (4 * 5 * P * 4) / 3); // five fundable comps

        vm.recordLogs();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 total;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != COMP_WIN_SIG) continue;
            address winner = address(uint160(uint256(logs[i].topics[1])));
            (uint32 n,) = abi.decode(logs[i].data, (uint32, uint256));
            total += n;
            (uint256 banked,) = CrapsViews(ContractAddresses.CRAPS).passCreditsOf(winner);
            assertGe(banked, n, "the real CrapsBattle holds less than the comp event announced");
        }
        assertEq(total, 5, "the five funded comps did not bank on the real contract");

        // The real gate: anyone who is not the Game is refused.
        vm.expectRevert(CrapsBattle.OnlyGame.selector);
        CrapsViews(ContractAddresses.CRAPS).creditPasses(address(1), 1, 0);
    }

    /// @dev WORST-CASE GAS, on the real Craps door: a comp-mode draw with every non-comp cell
    ///      populated, six cold pass recipients on the shipped `CrapsBattle`, multiple comps a
    ///      slot, and the full one-batch FLIP leg — against both ceilings, beside the sub-
    ///      threshold baseline the stage carried before.
    function test_gas_theWorstCaseCompDrawFitsTheEnvelope() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsViews()).code);
        vm.etch(ContractAddresses.GAME, address(new JackpotCompHarness()).code);
        JackpotCompHarness g = JackpotCompHarness(ContractAddresses.GAME);
        // 192 holders a bucket: six comp draws land on six DISTINCT wallets (asserted below),
        // so the measurement carries six genuinely cold pass writes.
        g.seedAllTraits(LVL, 192);
        uint256 snap = vm.snapshotState();

        g.seedBudgetFor(LVL, (4 * 13 * P * 4) / 3); // thirteen fundable comps over six slots
        vm.recordLogs();
        uint256 before = gasleft();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        uint256 compGas = before - gasleft();
        {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            address[6] memory seenW;
            uint256 distinct;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != COMP_WIN_SIG) continue;
                address w = address(uint160(uint256(logs[i].topics[1])));
                bool dup;
                for (uint256 j; j < distinct; ++j) {
                    if (seenW[j] == w) dup = true;
                }
                if (!dup) seenW[distinct++] = w;
            }
            assertEq(distinct, 6, "the worst case did not land six distinct cold recipients");
        }

        vm.revertToState(snap);
        g.seedBudgetFor(LVL, ((4 * P - 750) * 4) / 3); // one granule under the threshold
        before = gasleft();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        uint256 baseGas = before - gasleft();

        emit log_named_uint("comp-mode draw gas (worst case)", compGas);
        emit log_named_uint("sub-threshold draw gas (baseline)", baseGas);
        assertLt(compGas, 10_000_000, "the comp draw broke the 10M soft target on its own");
        assertLt(compGas, 16_777_216, "the comp draw broke the EIP-7825 hard ceiling on its own");
    }

    /// @dev A broken Craps wire fails the whole jackpot transaction loudly — never a silent
    ///      skip that strands the comp quadrant's budget.
    function test_aBrokenCrapsWireFailsTheWholeDrawLoudly() public {
        h.seedAllTraits(LVL, 8);
        craps.setRevertAll(true);
        _seedNear(4 * P);
        vm.expectRevert(bytes("craps-wiring-broken"));
        h.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
    }
}
