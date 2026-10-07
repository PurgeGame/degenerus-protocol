// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {Vm} from "forge-std/Vm.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Foundry isolation resets basefee to zero for a promoted non-static call.
/// Set it inside that transaction, then measure only the nested, unmodified Game
/// call. Fixture setup and this adapter are excluded; add mineFlip's 21,064 intrinsic.
contract BattlePaidMinerProbe {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(address game, address miner, uint256 supplied)
        external returns (bool ok, Vm.Gas memory used, bytes memory reason)
    {
        VM.fee(1 gwei);
        VM.prank(miner);
        (ok, reason) = game.call{gas: supplied}(abi.encodeWithSignature("mineFlip()"));
        used = VM.lastCallGas();
    }
}

/// @dev Test-only storage construction. Every measured worker is the deployed production
/// bytecode, including Game -> Miner -> Advance -> Jackpot -> Draw -> Craps -> JackpotBattle.
contract BattleConstructionGameSeed is DegenerusGameStorage, WalletSeed {
    function seedMinerPass(address miner, uint256 packed) external {
        _registerWallet(miner, type(uint256).max); mintPacked_[_walletIdOf(miner)] = packed; }

    function seedSession(uint24 ceiling, uint24 day, uint256 word) external {
        level = ceiling - 1;
        purchaseStartDay = day - 1;
        dailyIdx = day - 1;
        rngRequestDay = day;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = word;
        rngLockedFlag = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _setRngComplete(false);
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _recordDailyRng(day - 1, word);
        _recordDailyRng(day, word);
        dailyTicketBudgetsPacked = _JACKPOT_BATTLE_PENDING;
    }

    function seedQueue(uint24 target, uint32[] calldata ids) external {
        for (uint256 i; i < ids.length; ++i) _queueEntries(ids[i], target, 4, true);
    }

    function runDraw(uint24 ceiling, uint256 word, uint256 allowance)
        external returns (MineFlipGas.Result memory)
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSignature("runPurchaseJackpotBattle(uint24,uint256,uint256)", ceiling, word, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    function collectProbe(uint24 ceiling, uint256 word) external returns (uint32[] memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_DRAW_MODULE.delegatecall(
            abi.encodeWithSignature("collectProbe(uint24,uint256)", ceiling, word)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint32[]));
    }
}

/// @dev Exposes only the existing production draw loop for component calibration.
contract BattleConstructionDrawProbe is DegenerusGameJackpotDrawModule {
    function collectProbe(uint24 ceiling, uint256 word) external view returns (uint32[] memory players) {
        (players,,) = _collectJackpotChunkWithLevels(ceiling, word, 0, 150, _jackpotDrawLevels(ceiling, 0));
    }
}

contract BattleConstructionTableSeed is CrapsBattleStorage {
    /// @dev A normal (not detached) paid daily field. Counts affect seal arithmetic, never
    /// append iteration. Own/day/high seats make every nonempty seal accounting branch live.
    function seedPaidField(uint24 day) external {
        _bonus = uint256(day) + 1;
        _boostBudget[day] = 1;
        uint256 daySlot = uint256(day) * _BONUS_SLOTS_PER_DAY;
        uint64 slot = uint64(daySlot + _BONUS_PERIODS_PER_DAY);
        _dayTickets[daySlot] = 50 + 25 * _DT_ALL_HIGH;
        // Opened events already carry their advertised fee and high-lane terms at lock.
        _battles[bytes32(uint256(slot))] = 50
            | ((_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT)
            | (_BG_TERMS_FROZEN << _BG_TERM_TIER_SHIFT);
        _highField[bytes32(uint256(slot))] = 25;
        for (uint256 i = 1; i <= 50; ++i) {
            _storeBet((uint256(slot) << 64) | i, uint160(0x310000 + i));
            _storeBet((daySlot << 64) | i, uint160(0x320000 + i));
        }
    }

    function seedBoards(uint32[] calldata ids) external {
        // Seven legal chips, including the last leg: decode executes all ten iterations.
        uint32 chips = uint32((3 << 9) | (3 << 12) | (1 << 27));
        uint256 preference = (CrapsPreferenceLib.compress(chips) << CrapsPreferenceLib.SHIFT)
            | CrapsPreferenceLib.INITIALIZED;
        for (uint256 i; i < ids.length; ++i) _passCreditsById[ids[i]] = preference;
    }
}

contract JackpotBattleConstructionGasTest is DeployProtocol {
    uint24 private constant CEILING = 40;
    uint256 private constant WORD = 0xD1CEB00C;
    address private constant MINER = address(0xA11CE888);
    bytes private gameCode;
    bytes private tableCode;
    uint64 private slot;
    BattlePaidMinerProbe private paidProbe;

    function setUp() public {
        _deployProtocol(false);
        gameCode = address(game).code;
        // DeployProtocol exposes test readers. Measurements use the exact production facade.
        tableCode = type(CrapsBattle).runtimeCode;
        vm.warp(100 days + 82_620 + 1 hours);
        paidProbe = new BattlePaidMinerProbe();
    }

    function _seed(uint256 target, uint8 shape) private {
        uint24 day = GameTimeLib.currentDayIndex();
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
        vm.etch(address(crapsBattle), type(BattleConstructionTableSeed).runtimeCode);
        BattleConstructionGameSeed gs = BattleConstructionGameSeed(address(game));
        BattleConstructionTableSeed ts = BattleConstructionTableSeed(address(crapsBattle));
        gs.seedSession(CEILING, day, WORD);
        ts.seedPaidField(day - 1);
        uint256 battleWord = uint256(keccak256(abi.encode(WORD, CEILING, keccak256("far-future-coin"))));
        uint256 first = uint256(keccak256(abi.encode(battleWord, uint256(0)))) % 99;
        for (uint24 offset; offset < 99; ++offset) {
            // Shape 0 combines all 99 cold eligibility reads with a complete unique-wallet
            // chunk. Shape 1 maximizes singleton visits; shape 2 exercises circular fragments.
            uint256 count = shape == 0 ? (offset == first ? 500 : 1) : shape;
            uint32[] memory players = new uint32[](count);
            for (uint256 i; i < count; ++i) {
                // Every wallet ID has low byte zero. A full unique chunk hits all 1,225
                // pairwise exact comparisons in JackpotBattleFieldLib.prepare.
                players[i] = uint32((0x100000 + uint256(offset) * 1000 + i) << 8);
            }
            gs.seedQueue(CEILING + 1 + offset, players);
            ts.seedBoards(players);
        }
        vm.etch(address(crapsBattle), tableCode);
        vm.etch(address(game), gameCode);
        uint256 added = target * 10_000;
        uint256 pool = added * PriceLookupLib.priceForLevel(CEILING) * 200 / 1000;
        vm.prank(address(game));
        JackpotBattle(address(crapsBattle)).lockJackpotBattle(day, pool, CEILING);
        (slot,,,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        (CrapsBattleStorage.JackpotRound memory round,,) = JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        assertEq(round.added, added);
        assertEq(round.paidCount, 100);
        assertGt(round.paidUnits, round.paidCount, "high-seat seal branch must be present");
        // A depleted comp lane is reachable and makes its later credit a cold zero-to-nonzero
        // write. Preserve the adjacent tombstone flag and the unused upper slot bits.
        bytes32 laneSlot = bytes32(uint256(1));
        vm.store(address(coin), laneSlot, bytes32(uint256(vm.load(address(coin), laneSlot))
            & ~(uint256(type(uint128).max) << 8)));
        assertEq(coin.crapsCompAllowance(), 0);
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
    }

    function _cool() private {
        vm.cool(address(game)); vm.cool(address(crapsBattle)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(ContractAddresses.GAME_MINER_MODULE); vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE); vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        vm.cool(ContractAddresses.JACKPOT_BATTLE);
    }

    function _worker() private returns (uint256 used) {
        _cool();
        uint256 start = gasleft();
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: 10_000_000}(
            CEILING, WORD, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 100_000
        );
        used = start - gasleft();
        emit log_named_uint("cold battle worker gas incl facade delegate", used);
        assertTrue(result.progressed);
        assertFalse(result.done, "construction must not also simulate the battle");
        assertLt(used, GasBounds.JACKPOT_BATTLE_DRAW, "full worker must fit atomic admission bound");
    }

    function test_Cold50UniqueCollisionBoardsInitializeAppendSealWithinBound() public {
        _seed(50, 0);
        uint256 priorComps = coin.crapsCompAllowance();
        vm.recordLogs();
        _worker();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint32[] memory players = new uint32[](50);
        uint256 n;
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].topics[0] != keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)")) continue;
            uint32 player = uint32(uint256(entries[i].topics[3]));
            (uint256 units, uint32 chips) = abi.decode(entries[i].data, (uint256, uint32));
            assertEq(player & 255, 0);
            assertEq(units, 1);
            assertEq(chips, (3 << 9) | (3 << 12) | (1 << 27));
            for (uint256 j; j < n; ++j) assertTrue(players[j] != player, "full collision scan requires unique wallets");
            players[n++] = player;
        }
        assertEq(n, 50);
        (CrapsBattleStorage.JackpotRound memory round, uint256 board,) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        assertEq(round.drawnCount, 50);
        assertEq(round.drawnUnits, 50);
        assertEq(uint32(board), 150);
        assertEq(round.word, round.drawWord);
        assertGt(round.word, 0);
        assertGt(round.potRemainder, 0, "fresh remainder slot must exercise its write");
        assertGt(coin.crapsCompAllowance(), priorComps, "real FLIP comps sink must execute");
    }

    function test_Cold500AwardMaximumResumesAndSealsWithoutRepeatedInitialization() public {
        _seed(500, 0);
        uint256 word;
        for (uint256 i; i < 10; ++i) {
            _worker();
            (CrapsBattleStorage.JackpotRound memory round,,) = JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
            if (i == 0) word = round.drawWord;
            assertEq(round.drawWord, word);
            assertEq(round.drawnCount, (i + 1) * 50);
            assertEq(round.word == 0, i < 9);
        }
    }

    function test_CachedLevelListMatchesResumedConstructionTranscript() public {
        _seed(500, 3);
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: 30_000_000}(
            CEILING, WORD, 30_000_000
        );
        assertTrue(result.progressed);
        assertFalse(result.done, "construction remains separate from simulation");
        bytes32 transcript = keccak256(abi.encode(vm.getRecordedLogs()));
        (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 resolved) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        assertEq(round.drawnCount, 500, "one invocation must reuse the list across ten chunks");
        assertGt(round.word, 0, "the final chunk seals the field");
        assertEq(resolved, 0);
        bytes32 state = keccak256(abi.encode(round, board, resolved));
        uint256 comps = coin.crapsCompAllowance();
        assertTrue(vm.revertToStateAndDelete(snapshot));

        vm.recordLogs();
        for (uint256 i; i < 10; ++i) {
            result = BattleConstructionGameSeed(address(game)).runDraw{gas: 10_000_000}(
                CEILING, WORD, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 100_000
            );
            assertTrue(result.progressed);
            assertFalse(result.done);
            (round, board, resolved) = JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
            assertEq(round.drawnCount, (i + 1) * 50, "reference rebuilds the list once per chunk");
        }
        assertEq(keccak256(abi.encode(vm.getRecordedLogs())), transcript, "identical ordered award and seal events");
        assertEq(keccak256(abi.encode(round, board, resolved)), state, "identical cursor, field and sealed terms");
        assertEq(coin.crapsCompAllowance(), comps, "identical final comp accounting");
    }

    function test_ColdSingletonVisitBranchWithinBound() public { _seed(50, 1); _worker(); }
    function test_ColdFragmentedCircularVisitBranchWithinBound() public { _seed(50, 3); _worker(); }

    function test_ColdCollectionComponentAcrossQueueWordBoundaries() public {
        bytes memory probe = type(BattleConstructionDrawProbe).runtimeCode;
        uint256 pristine = vm.snapshotState();
        uint8[11] memory shapes = [uint8(0), 1, 2, 3, 7, 8, 9, 15, 16, 17, 31];
        for (uint256 i; i < shapes.length; ++i) {
            _seed(150, shapes[i]);
            vm.etch(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, probe);
            _cool();
            uint256 word = uint256(keccak256(abi.encode(WORD, CEILING, keccak256("far-future-coin"))));
            uint256 start = gasleft();
            uint32[] memory players = BattleConstructionGameSeed(address(game)).collectProbe(CEILING, word);
            uint256 used = start - gasleft();
            emit log_named_uint("collection queue length (0 = concentrated500)", shapes[i]);
            emit log_named_uint("cold production collection component", used);
            assertEq(players.length, 50);
            assertLt(used, 1_500_000, "collection branch calibration envelope");
            assertTrue(vm.revertToState(pristine));
        }
    }

    function test_AdmissionDefersAtPolicyAndActualGasThresholdsWithoutCommittingField() public {
        _seed(150, 0);
        uint256 comps = coin.crapsCompAllowance();
        _cool();
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: 10_000_000}(
            CEILING, WORD, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 1_999
        );
        assertFalse(result.progressed, "insufficient remaining policy must defer before prepare");
        _cool();
        result = BattleConstructionGameSeed(address(game)).runDraw{gas: GasBounds.JACKPOT_BATTLE_DRAW}(
            CEILING, WORD, 9_000_000
        );
        assertFalse(result.progressed, "insufficient actual gas must defer before prepare");
        vm.etch(address(game), gameCode);
        _cool();
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        vm.prank(MINER);
        game.mineFlip{gas: GasBounds.JACKPOT_BATTLE_DRAW}();
        (CrapsBattleStorage.JackpotRound memory round,,) = JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        assertEq(round.drawWord, 0, "deferral must not initialize a draw");
        assertEq(round.drawnCount, 0);
        assertEq(round.word, 0, "deferral must not seal a field");
        assertEq(coin.crapsCompAllowance(), comps);
        assertEq(coinflip.coinflipAmount(MINER), 0, "no-work deferral cannot pay a miner");
    }

    function test_ColdProductionMineFlipConstructionSealAndMinerPaymentWithin10M() public {
        _seed(150, 0);
        vm.etch(address(game), gameCode);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.DailyPhase), "fixture must select the real daily phase");
        uint256 beforeReward = coinflip.coinflipAmount(MINER);
        _cool();
        (bool ok, Vm.Gas memory observed,) = paidProbe.run(address(game), MINER, 12_000_000);
        assertTrue(ok);
        uint256 used = observed.gasTotalUsed + 21_064;
        emit log_named_uint("cold complete mineFlip battle construction incl intrinsic", used);
        assertLt(used, 10_000_000);
        (CrapsBattleStorage.JackpotRound memory round,, uint64 resolved) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        assertEq(round.drawnCount, 150);
        assertGt(round.word, 0);
        assertEq(resolved, 0, "construction call must stop before simulations");
        assertGt(coinflip.coinflipAmount(MINER), beforeReward, "real miner compensation must be included");
    }
}
