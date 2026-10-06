// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsPreferenceStore} from "../craps/CrapsPreferenceStore.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev The production jackpot module in its own storage, plus seeders and test state readers. NO
///      production logic is overridden.
contract FlipDrawHarness is DegenerusGameJackpotModule, BucketSeed {
    /// @dev Mirror of `_calcDailyCoinBudget` solved for the pool at storage level 0 (0.01 ETH):
    ///      budget = pool * 1000 / (0.01 * 400) = pool * 250.
    function seedBudgetFor(uint24 lvl, uint256 coinBudget) external {
        levelPrizePool[lvl - 1] = (coinBudget * PriceLookupLib.priceForLevel(level) * 400) / PRICE_COIN_UNIT;
    }

    function coinBudgetOf(uint24 lvl) external view returns (uint256) {
        return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(level) * 400);
    }

    /// @dev Every trait byte gets `count` distinct holders, so every pull resolves a winner.
    function seedAllTraits(uint24 lvl, uint256 count) external {
        for (uint256 t; t < 256; ++t) {
            for (uint256 i; i < count; ++i) {
                _seedBucket(lvl, uint8(t), address(uint160((t << 32) | (i + 1))), 1);
            }
        }
    }

    /// @dev Only quadrant `q`'s 64 trait bytes get holders: pulls on the other quadrants miss.
    function seedQuadrant(uint24 lvl, uint256 q, uint256 count) external {
        for (uint256 t = q * 64; t < q * 64 + 64; ++t) {
            for (uint256 i; i < count; ++i) {
                _seedBucket(lvl, uint8(t), address(uint160((t << 32) | (i + 1))), 1);
            }
        }
    }


    function today() external view returns (uint24) {
        return _simulatedDayIndex();
    }

    /// @dev The real JackpotBattle reads the Game's storage (daily words) through this.
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function playerActivityScore(address) external pure returns (uint256) {
        return 0;
    }
}

/// @dev Records every FLIP credit that crosses the boundary.
contract FlipDrawCoinflipDouble {
    address[] public players;
    uint256[] public amounts;
    uint256 public batches;
    uint256 public total;

    function creditFlipBatch(address[] calldata p, uint256[] calldata a) external {
        for (uint256 i; i < p.length; ++i) {
            if (p[i] != address(0) && a[i] != 0) {
                players.push(p[i]);
                amounts.push(a[i]);
                total += a[i];
            }
        }
        ++batches;
    }

    function count() external view returns (uint256) {
        return players.length;
    }
}

/// @dev The table's double: records any call it receives. Neither draw seats a ticket or directly banks passes; qualifying battle winners are paid inside the table's own finalization.
contract NoCrapsCallsDouble is CrapsPreferenceStore {
    uint256 public creditPassesCalls;
    uint256 public vaultCompCalls;

    function creditPasses(address, uint32, uint32) external {
        ++creditPassesCalls;
    }

    function vaultComp(uint256) external returns (uint256) {
        ++vaultCompCalls;
        return 0;
    }
}

/// @title LevelOneFlipDraw — level 1's trait-matched FLIP draw
/// @notice `payDailyFlipJackpot` pays 0.25% of the previous level's recorded pool as up to 50
///         equal whole-100-FLIP shares to trait-matched level-1 ticket holders on the day's main
///         board — FLIP only, no craps seat, reservation or pass ever touches CrapsBattle. The
///         daily jackpot battle is tested through the real advance in JackpotMergeAdvance.t.sol.
contract LevelOneFlipDrawTest is Test {
    FlipDrawHarness internal h;
    FlipDrawCoinflipDouble internal coinflip;
    NoCrapsCallsDouble internal craps;

    uint24 internal constant LVL = 1;
    uint256 internal constant WORD = uint256(keccak256("level-one-flip-draw-word"));
    uint256 internal constant UNIT = 100;
    uint256 internal constant CAP_MAX = 50;

    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(uint32,uint24,uint8,uint256,uint256)");
    bytes32 internal constant CRAPS_PASSES_CREDITED_SIG = keccak256("CrapsPassesCredited(address,bool,uint256)");
    bytes32 internal constant CRAPS_SLIP_PLACED_SIG = keccak256("CrapsSlipPlaced(address,uint256)");

    function setUp() public {
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 5) * 1 days + 82_620 + 1 hours);
        h = new FlipDrawHarness();
        // Advance records the level-one board before entering the FLIP leg.
        vm.prank(ContractAddresses.GAME);
        h.emitDailyWinningTraits(WORD);
        vm.etch(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, address(new DegenerusGameJackpotDrawModule()).code);
        assertGt(ContractAddresses.GAME_JACKPOT_DRAW_MODULE.code.length, 0, "the delegated draw has code");
        vm.etch(ContractAddresses.COINFLIP, address(new FlipDrawCoinflipDouble()).code);
        vm.etch(ContractAddresses.CRAPS, address(new NoCrapsCallsDouble()).code);
        coinflip = FlipDrawCoinflipDouble(ContractAddresses.COINFLIP);
        craps = NoCrapsCallsDouble(ContractAddresses.CRAPS);
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    function _runTrait() internal returns (Vm.Log[] memory logs) {
        vm.recordLogs();
        h.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        logs = vm.getRecordedLogs();
    }

    // ── The draw's shares ──────────────────────────────────────────────────

    /// @dev Deep buckets, budget for 125 whole units: cap saturates at CAP_MAX and the
    ///      2,500-FLIP sub-share remainder (125 units is not a multiple of 50) is never minted.
    function test_fiftyWinnersEqualSharesRemainderUnminted() public {
        h.seedAllTraits(LVL, 4);
        h.seedBudgetFor(LVL, 12_500);
        assertEq(h.coinBudgetOf(LVL), 12_500, "budget seed did not round-trip");
        Vm.Log[] memory logs = _runTrait();

        assertEq(_countSig(logs, FLIP_WIN_SIG), CAP_MAX, "50 winners");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, 2 * UNIT, "equal 200-FLIP share");
        }
        assertEq(coinflip.batches(), 1, "one batch");
        assertEq(coinflip.total(), CAP_MAX * 2 * UNIT, "credited total != 50 * amount");
        assertLt(coinflip.total(), 12_500, "the sub-share remainder was minted");
        assertEq(craps.creditPassesCalls(), 0, "the draw banked a craps pass");
        assertEq(craps.vaultCompCalls(), 0, "the draw seated or reserved a craps window");
    }

    /// @dev Below 50 whole units, the cap is the unit count itself: 31 units pays 31 winners of
    ///      exactly one 100-FLIP unit each, with nothing left over.
    function test_smallBudgetCapsAtUnitCount() public {
        h.seedAllTraits(LVL, 4);
        h.seedBudgetFor(LVL, 3_125);
        Vm.Log[] memory logs = _runTrait();

        assertEq(_countSig(logs, FLIP_WIN_SIG), 31, "cap = units when units < 50");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, UNIT, "one whole unit per winner");
        }
        assertEq(coinflip.total(), 31 * UNIT, "credited total != 31 * one unit");
        assertEq(craps.creditPassesCalls(), 0, "the draw banked a craps pass");
        assertEq(craps.vaultCompCalls(), 0, "the draw seated or reserved a craps window");
    }

    /// @dev A budget under one whole unit skips entirely: no winner, no batch, nothing minted.
    function test_belowOneUnitSkipsEntirely() public {
        h.seedAllTraits(LVL, 4);
        h.seedBudgetFor(LVL, 99);
        Vm.Log[] memory logs = _runTrait();

        assertEq(_countSig(logs, FLIP_WIN_SIG), 0, "no winner under one whole unit");
        assertEq(coinflip.batches(), 0, "no batch when nothing was won");
    }

    /// @dev Only one quadrant's winning trait has holders: three pulls in four miss their bucket
    ///      and are skipped outright — the shares those misses would have paid are never minted,
    ///      only the found winners' shares are.
    function test_emptyBucketsSkipWithoutMinting() public {
        h.seedQuadrant(LVL, 0, 4);
        h.seedBudgetFor(LVL, 625_000);
        Vm.Log[] memory logs = _runTrait();

        // units = 6,250, cap = 50, amount = 125 * UNIT; only i % 4 == 0 ever finds a winner
        // across the 50 pulls (i = 0, 4, .., 48), so 13 of the 50 shares are ever paid.
        uint256 amount = 125 * UNIT;
        assertEq(_countSig(logs, FLIP_WIN_SIG), 13, "only the seeded quadrant's pulls resolve");
        assertEq(coinflip.total(), 13 * amount, "credited total != the found winners' shares");
        assertLt(coinflip.total(), CAP_MAX * amount, "the skipped shares were minted anyway");
    }

    /// @dev The real CrapsBattle at CRAPS sees only preference reads, never emits a pass credit or a slip
    ///      placement, and never logs anything at all — the trait-matched draw is FLIP-only.
    function test_realCrapsTableStaysUntouched() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsViews()).code);
        h.seedAllTraits(LVL, 4);
        h.seedBudgetFor(LVL, 250_000);

        Vm.Log[] memory logs = _runTrait();
        assertGt(_countSig(logs, FLIP_WIN_SIG), 0, "fixture must actually draw winners");
        assertEq(_countSig(logs, CRAPS_PASSES_CREDITED_SIG), 0, "a craps pass was credited");
        assertEq(_countSig(logs, CRAPS_SLIP_PLACED_SIG), 0, "a craps slip was placed");
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != ContractAddresses.CRAPS, "the craps table emitted something");
        }
    }

    /// @dev Fuzzed budgets never overspend and never pay more shares than CAP_MAX, whole buckets.
    function test_fuzz_theDrawNeverOverspendsOrExceedsTheCap(uint256 seed) public {
        uint256 b = bound(seed, 1, 5_000) * 250;
        h.seedAllTraits(LVL, 4);
        h.seedBudgetFor(LVL, b);
        Vm.Log[] memory logs = _runTrait();

        uint256 units = b / UNIT;
        uint256 cap = units < CAP_MAX ? units : CAP_MAX;
        uint256 amount = cap == 0 ? 0 : (units / cap) * UNIT;
        uint256 paid = _countSig(logs, FLIP_WIN_SIG);
        assertGt(cap, 0, "the populated-board fixture has a payable budget");
        assertEq(paid, cap, "every populated-board share resolves a winner");
        assertLe(paid, cap, "more winners than the cap");
        assertEq(coinflip.count(), paid, "each winner reaches the real credit boundary");
        assertEq(coinflip.batches(), 1, "the populated draw credits one batch");
        assertEq(coinflip.total(), paid * amount, "credited total != paid winners * amount");
        assertLe(coinflip.total(), b, "overspent");
        assertEq(craps.creditPassesCalls(), 0, "the draw banked a craps pass");
        assertEq(craps.vaultCompCalls(), 0, "the draw seated or reserved a craps window");
    }
}
