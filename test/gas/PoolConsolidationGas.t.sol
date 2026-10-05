// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {FreshWordLeg} from "./PurchaseDailyWorstCase.t.sol";
import {CenturyBafScores, CenturyNativeGasHost} from "./AdvanceCenturyConsolidationGas.t.sol";

/// @dev Last-purchase-day state one level below `lvl`; the real request pre-increments the level.
///      A Decimator event of `decEntrants` entrants is open for `lvl` (sealing is constant work
///      regardless of the entrant population).
contract ConsolidationLevelSeeder is DegenerusGame {
    function seed(uint24 lvl, uint128 nextPool, uint128 futurePool, uint40 decEntrants) external {
        uint24 day = _simulatedDayIndex();
        level = lvl - 1;
        purchaseStartDay = day - 8;
        dailyIdx = day - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        currentPrizePool = 0;
        _setPrizePools(nextPool, futurePool);
        levelPrizePool[lvl - 2] = (uint256(nextPool) * 8) / 10;
        levelPrizePool[lvl - 1] = (uint256(nextPool) * 9) / 10;
        yieldAccumulator = 18.25 ether + uint256(nextPool) / 400;
        if (decEntrants != 0) {
            _setDecWindowOpen(true);
            decBattleRounds[lvl].count = decEntrants;
        }
    }
}

/// @title PoolConsolidationGas — the consolidation chunk of every level kind, cold.
/// @notice The chunk is `runDailyPhase`'s last-purchase-day branch: level prize pool record, the
///         century prize pool push at x00, the growth round seal, the yield surplus distribution,
///         `_consolidatePoolsAndRewardJackpots` (skim, x00 yield dump, BAF arming on a winning x0
///         flip or the skip mark plus the x00 incinerator resolve on a losing one, the Decimator
///         seal at x5 / x00, the x00 keep roll, the house's high-roller passes, the drawdown and the
///         pool settlement), the phase flags and the level quest roll. Each case seeds the level
///         below, drives the real request and VRF answer, the word application and the purchase
///         battle through the production modules, then measures the consolidation call alone with
///         every engine account cold. The three yield surplus recipients start with empty balance
///         slots, so each surplus credit is a zero-to-nonzero write.
abstract contract PoolConsolidationFixture is FreshWordLeg {
    uint8 internal constant STAGE_PURCHASE_BATTLE = 17;
    uint8 internal constant STAGE_ENTERED_JACKPOT = 7;
    uint24 internal constant DAY = 400;
    uint128 internal constant NEXT_POOL = 3500 ether;
    uint128 internal constant FUTURE_POOL = 100 ether;
    uint256 internal constant WIN_WORD = 0x0ee7fcb287531227df7efcfddb3f0151121ee9e59765e743a190d8e26ee417fd;
    uint256 internal constant SKIP_WORD = WIN_WORD ^ 1;
    // WWXRP incinerator storage: `_incinHeader` slot 6, `_incinEntry` slot 7 (cum, player).
    uint256 internal constant INCIN_HEADER_SLOT = 6;
    uint256 internal constant INCIN_ENTRY_SLOT = 7;

    CenturyNativeGasHost internal host;
    address internal incineratorWinner;

    function _level() internal pure virtual returns (uint24);

    function _word() internal pure virtual returns (uint256);

    function _label() internal pure virtual returns (string memory);

    function _decEntrants() internal pure virtual returns (uint40) {
        return 0;
    }

    /// @dev Entries in the x00 incinerator book (a binary search of log2 steps).
    function _incineratorEntries() internal pure virtual returns (uint32) {
        return 0;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        uint24 lvl = _level();
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ConsolidationLevelSeeder).runtimeCode);
        ConsolidationLevelSeeder(payable(address(game))).seed(lvl, NEXT_POOL, FUTURE_POOL, _decEntrants());
        vm.etch(address(game), original);
        // Total obligations plus real surplus; nonzero stETH takes the mock's shares path.
        vm.deal(address(game), uint256(NEXT_POOL) + FUTURE_POOL + 68.25 ether + uint256(NEXT_POOL) / 400);
        mockStETH.mint(address(game), 50 ether);
        _armFreshWord(_word(), DAY);
        assertEq(game.level(), lvl, "the real request pre-increments the level");
        if (lvl % 100 == 0) CenturyBafScores.seedHead(address(jackpots), address(coinflip), address(game), DAY);
        if (_incineratorEntries() != 0) incineratorWinner = _seedIncinerator(lvl, _incineratorEntries(), _word());

        vm.etch(address(game), type(CenturyNativeGasHost).runtimeCode);
        host = CenturyNativeGasHost(payable(address(game)));
        host.publishOnly();
        for (uint256 reads; !host.prepareTicketsOnly{gas: 12_000_000}(); ++reads) {
            assertLt(reads, 64, "ticket prerequisites stalled");
        }
        host.applyOnly{gas: 12_000_000}();
        assertEq(game.rngWordForDay(DAY), _word(), "the day's word is the fulfilled word");
        // The purchase battle runs first; the first call that is not a battle step is the
        // consolidation, which is rolled back here and measured cold by the test.
        for (uint256 steps;; ++steps) {
            assertLt(steps, 40, "the purchase battle stalled");
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            MineFlipGas.Result memory r = host.dailyWith{gas: 12_000_000}(9_000_000);
            assertTrue(r.progressed, "the daily phase progresses");
            uint8 stage = _stageOf(vm.getRecordedLogs());
            if (stage == STAGE_PURCHASE_BATTLE) continue;
            assertEq(stage, STAGE_ENTERED_JACKPOT, "consolidation follows the battle");
            vm.revertToState(snap);
            break;
        }
        assertTrue(game.rngLocked(), "the daily lock is held at consolidation");
    }

    /// @dev A book of `count` unit-weight entries; only the binary search's probes and the found
    ///      entry are written (cum = (index + 1) ether, player 0x1C1E0000 + index), which yields the
    ///      same search path as a fully written book.
    function _seedIncinerator(uint24 bracket, uint32 count, uint256 rngWord) private returns (address winner) {
        uint256 total = uint256(count) * 1 ether;
        vm.store(
            address(wwxrp),
            keccak256(abi.encode(uint256(bracket), INCIN_HEADER_SLOT)),
            bytes32(total | (uint256(count) << 192))
        );
        uint256 roll = uint256(
            keccak256(abi.encodePacked(bytes32("WWXRP_INCIN_WINNER"), address(wwxrp), bracket, rngWord))
        ) % total;
        uint32 lo;
        uint32 hi = count - 1;
        while (lo < hi) {
            uint32 mid = lo + (hi - lo) / 2;
            _storeIncinEntry(bracket, mid);
            if ((uint256(mid) + 1) * 1 ether > roll) hi = mid;
            else lo = mid + 1;
        }
        _storeIncinEntry(bracket, lo);
        winner = address(uint160(0x1C1E0000 + uint256(lo)));
        (uint256 score, uint32 entries) = wwxrp.incineratorInfo(bracket);
        assertEq(score, total, "incinerator header layout");
        assertEq(entries, count, "incinerator header layout");
        (address player, uint256 cum) = wwxrp.incineratorEntryAt(bracket, lo);
        assertEq(player, winner, "incinerator entry layout");
        assertEq(cum, (uint256(lo) + 1) * 1 ether, "incinerator entry layout");
    }

    function _storeIncinEntry(uint24 bracket, uint32 index) private {
        bytes32 base = keccak256(abi.encode((uint256(bracket) << 32) | index, INCIN_ENTRY_SLOT));
        vm.store(address(wwxrp), base, bytes32((uint256(index) + 1) * 1 ether));
        vm.store(address(wwxrp), bytes32(uint256(base) + 1), bytes32(uint256(0x1C1E0000 + uint256(index))));
    }

    /// @dev Every account the consolidation can touch starts the measured call cold.
    function _coolAll() private {
        address[18] memory accounts = [
            address(game), address(advanceModule), address(jackpotModule), address(jackpotDrawModule),
            address(decimatorModule), address(jackpots), address(coinflip), address(wwxrp), address(quests),
            address(parimutuel), address(crapsBattle), address(crapsEngine), address(mockStETH), address(sdgnrs),
            address(vault), address(coin), address(gnrus), address(dgnrs)
        ];
        for (uint256 i; i < accounts.length; ++i) vm.cool(accounts[i]);
    }

    function _stageOf(Vm.Log[] memory logs) private pure returns (uint8 stage) {
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == keccak256("Advance(uint8,uint24)")) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    function _housePasses(Vm.Log[] memory logs) private pure returns (uint256 passes) {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length > 1 && logs[i].topics[0] == keccak256("CrapsPassesCredited(address,bool,uint256)")
                    && address(uint160(uint256(logs[i].topics[1]))) == ContractAddresses.SDGNRS
            ) {
                (bool high, uint256 n) = abi.decode(logs[i].data, (bool, uint256));
                if (high) passes += n;
            }
        }
    }

    /// @dev Balance slot (`balancesPacked`, game slot 7) of a yield surplus recipient.
    function _balanceSlot(address who) private pure returns (bytes32) {
        return keccak256(abi.encode(who, uint256(7)));
    }

    /// @dev How many of the three yield surplus recipients hold an empty balance slot (a credit to one
    ///      is a zero-to-nonzero write).
    function _emptyRecipientSlots() private view returns (uint256 n) {
        address[3] memory who = [ContractAddresses.VAULT, ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        for (uint256 i; i < 3; ++i) {
            if (game.extsload(_balanceSlot(who[i])) == bytes32(0)) ++n;
        }
    }

    function test_ConsolidationCold() public {
        uint24 lvl = _level();
        bool x0 = lvl % 10 == 0;
        bool win = _word() & 1 == 1;
        assertEq(_emptyRecipientSlots(), 3, "every yield surplus credit is a zero-to-nonzero write");
        _coolAll();
        vm.recordLogs();
        MineFlipGas.Result memory result = host.dailyWith{gas: 12_000_000}(9_000_000);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        emit log_named_uint(string.concat("consolidation_", _label(), "_cold_including_intrinsic"), used);
        emit log_named_uint("house_high_passes", _housePasses(logs));

        assertTrue(result.progressed && result.done, "the consolidation completes in one call");
        assertEq(_stageOf(logs), STAGE_ENTERED_JACKPOT, "the jackpot phase is entered");
        assertTrue(game.jackpotPhase(), "jackpot phase flag set");
        (uint8 kind,,,) = host.bafWork();
        assertEq(kind, x0 && win ? 7 : 0, "a winning x0 flip arms the BAF award stage");
        assertEq(_countTopic(logs, keccak256("BafSkipped(uint24,uint24)")), x0 && !win ? 1 : 0, "a losing x0 flip skips");
        uint256 resolved = _countTopic(logs, keccak256("IncineratorResolved(uint24,address,uint256,uint256,uint256)"));
        assertEq(resolved, lvl % 100 == 0 && !win ? 1 : 0, "a skipped century resolves the incinerator");
        if (resolved != 0) _checkIncinerator(logs);
        assertEq(
            _countTopic(logs, keccak256("DecimatorResolved(uint24,uint256,uint256,uint64)")),
            _decEntrants() != 0 ? 1 : 0,
            "an entered Decimator event seals"
        );
        assertEq(_countTopic(logs, keccak256("YieldSurplusDistributed(uint256)")), 1, "surplus distributes");
        assertEq(_countTopic(logs, keccak256("GrowthRoundSealed(uint24,bool)")), 1, "growth round seals");
        assertEq(_countTopic(logs, keccak256("LevelQuestRolled(uint24,uint8,uint8,uint256)")), 1, "level quest rolls");
        assertEq(_dailyLegLogs(logs), 0, "consolidation pays no award");
        assertLt(used, GasBounds.POOL_CONSOLIDATION, "consolidation exceeds its declared bound");
    }

    function _checkIncinerator(Vm.Log[] memory logs) private {
        bytes32 sig = keccak256("IncineratorResolved(uint24,address,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != sig) continue;
            assertEq(address(uint160(uint256(logs[i].topics[2]))), incineratorWinner, "the seeded book's winner");
            (uint256 award,,) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            assertGt(award, 0, "the lost armed-day book funds a FLIP award");
            emit log_named_uint("incinerator_flip_award", award);
        }
    }
}

/// @notice x00, winning flip: BAF arming (20%), Decimator seal, century pool push, yield dump, keep
///         roll and house passes.
contract PoolConsolidationCenturyWinGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 100;
    }

    function _word() internal pure override returns (uint256) {
        return WIN_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "x00_win";
    }

    function _decEntrants() internal pure override returns (uint40) {
        return 1_000_000;
    }
}

/// @notice x00, losing flip: the skip mark and the incinerator resolve over a 2^20-entry burner
///         book (20 binary-search probes) paying the armed day's lost book as a FLIP credit to a
///         fresh wallet, plus the Decimator seal and the century steps.
contract PoolConsolidationCenturySkipGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 100;
    }

    function _word() internal pure override returns (uint256) {
        return SKIP_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "x00_skip_incinerator";
    }

    function _decEntrants() internal pure override returns (uint40) {
        return 1_000_000;
    }

    function _incineratorEntries() internal pure override returns (uint32) {
        return 1 << 20;
    }
}

/// @notice x0 (level 90), winning flip: BAF arming (10%), house passes, drawdown.
contract PoolConsolidationX0WinGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 90;
    }

    function _word() internal pure override returns (uint256) {
        return WIN_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "x0_win";
    }
}

/// @notice x0 (level 90), losing flip: the skip mark.
contract PoolConsolidationX0SkipGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 90;
    }

    function _word() internal pure override returns (uint256) {
        return SKIP_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "x0_skip";
    }
}

/// @notice Level 50, winning flip: BAF arming at 20%.
contract PoolConsolidationFiftyWinGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 50;
    }

    function _word() internal pure override returns (uint256) {
        return WIN_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "x50_win";
    }
}

/// @notice x5 (level 85): the Decimator seal of an entered event (10% of the future pool).
contract PoolConsolidationX5DecimatorGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 85;
    }

    function _word() internal pure override returns (uint256) {
        return WIN_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "x5_decimator";
    }

    function _decEntrants() internal pure override returns (uint40) {
        return 1_000_000;
    }
}

/// @notice An ordinary level (87): no BAF, no Decimator.
contract PoolConsolidationOrdinaryGas is PoolConsolidationFixture {
    function _level() internal pure override returns (uint24) {
        return 87;
    }

    function _word() internal pure override returns (uint256) {
        return WIN_WORD;
    }

    function _label() internal pure override returns (string memory) {
        return "ordinary";
    }
}
