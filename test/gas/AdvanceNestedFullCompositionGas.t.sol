// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";
import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BattleRef} from "../craps/JackpotBattle.t.sol";
import {JackpotBoardFixtures} from "../fuzz/helpers/JackpotBoardFixtures.sol";
import {NestedSettlementFixture} from "./AdvanceNestedSettlementGas.t.sol";

contract FullRollBudgetSeeder is DegenerusGame {
    function setPreviousPool(uint24 level, uint256 amount) external {
        levelPrizePool[level] = amount;
    }

    function setFutureQueueOwner(uint24 level, uint256 lane, address owner) external {
        uint256[] storage queue = ticketQueue[_tqFarFutureKey(level)];
        uint256 packed = _tqWordAt(queue, lane);
        uint32 pos = uint32(packed >> ((lane & 7) << 5));
        uint24 key = _tqFarFutureKey(level);
        address previous = lvlEntryOwner[level][pos - 1].owner;
        lvlEntryOwner[level][pos - 1].owner = owner;
        delete entryOwnerPosition[key][previous];
        entryOwnerPosition[key][owner] = pos;
    }
}

/// @dev Make the replay a nested CALL even under --isolate. This yields the battle's own
///      execution cost without a top-level transaction's calldata intrinsic or the test's
///      memory/ABI wrapper, exactly the component replaced in the battle transaction.
contract JackpotBattleReplayMeter {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function replay(uint24 level, uint256[] calldata field, uint256 budget, uint256 word)
        external returns (uint256)
    {
        vm.prank(ContractAddresses.GAME);
        JackpotBattle(ContractAddresses.JACKPOT_BATTLE).resolve(level, field, budget, word);
        return vm.lastCallGas().gasTotalUsed;
    }
}

/// @notice Split-stage stress: fresh VRF, 365 days of failed vault settlement, golden grand,
///         redemption and 49 ETH awards in the daily transaction; 50 paying max-chip battle
///         runs in the next. Router overhead is included. Run with FOUNDRY_ISOLATE=true.
contract AdvanceNestedFullCompositionGas is NestedSettlementFixture {
    function _sufficient() internal pure override returns (bool) {
        return false;
    }

    function _comps() internal pure override returns (bool) {
        return true;
    }

    function _extras() internal pure override returns (bool) {
        return true;
    }

    function _router() internal pure override returns (bool) {
        return true;
    }

    /// @dev Pick cold wallets that the already-committed battle word pays, then put them in
    ///      the first seven levels the draw visits. This changes only the test fixture's owner
    ///      registry before measurement; the real Game still samples queues and runs the battle.
    function _seedPayingFutureWallets(uint256 dailyWord) private returns (uint256 battleWord) {
        uint24 purchaseLevel = LVL + 1;
        battleWord = uint256(keccak256(abi.encode(dailyWord, purchaseLevel, keccak256("far-future-coin"))));
        BattleRef probe = new BattleRef();
        address[56] memory paying;
        uint256 found;
        for (uint160 n = 1; found < paying.length && n < 100_000; ++n) {
            address candidate = address(uint160(0x5000000000) + n);
            // The field shares its dice, so a wallet's seat decides only its rotation turn: keep a
            // wallet whose run pays from every seat of a full field.
            bool pays = true;
            for (uint256 seat; seat < JACKPOT_BATTLE_ENTRANTS && pays; ++seat) {
                Craps.SlipResult memory r =
                    probe.run(battleWord, candidate, (type(uint24).max / 10 / 6) * 6, seat, JACKPOT_BATTLE_ENTRANTS);
                pays = r.stop == Craps.SlipStop.Goal || r.totalRolls == 200 || r.handsPlayed == 22;
            }
            if (pays) paying[found++] = candidate;
        }
        assertEq(found, paying.length, "could not seed a full paying field");

        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(FullRollBudgetSeeder).runtimeCode);
        uint256 entropy = battleWord;
        uint256 visited;
        uint256 assigned;
        for (uint256 pick; pick < 16 && assigned < paying.length; ++pick) {
            entropy = EntropyLib.hash2(entropy, pick);
            uint256 offset = entropy % 99;
            if ((visited >> offset) & 1 != 0) continue;
            visited |= uint256(1) << offset;
            uint24 target = purchaseLevel + 1 + uint24(offset);
            for (uint256 lane; lane < 8; ++lane) {
                FullRollBudgetSeeder(payable(address(game))).setFutureQueueOwner(target, lane, paying[assigned++]);
            }
        }
        vm.etch(address(game), realCode);
        assertEq(assigned, paying.length, "not enough distinct future levels were sampled");
    }

    function test_DailyAndBattleAreSeparateTransactions() public {
        vm.expectCall(
            ContractAddresses.WWXRP,
            abi.encodeWithSignature("mintPrize(address,uint256)", ContractAddresses.VAULT, 1 ether)
        );
        vm.recordLogs();
        game.mineFlip{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        uint256 used = _transactionGas();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethWins;
        uint256 battleRuns;
        uint256 goldenWins;
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_WIN_SIG) ++ethWins;
            if (topic == BATTLE_RUN_SIG) ++battleRuns;
            if (topic == keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)"))
            {
                ++goldenWins;
            }
            if (topic == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        assertEq(stage, STAGE_PURCHASE_DAILY, "purchase daily stage did not finish");
        assertEq(ethWins, PURCHASE_ETH_WINNERS, "ETH leg was not saturated");
        assertEq(battleRuns, 0, "battle must wait for the battle transaction");
        assertEq(goldenWins, 1, "golden grand was not resolved");
        emit log_named_uint("all_purchase_day_legs_including_intrinsic", used);
        assertLt(used, 10_500_000, "daily stage exceeds the 10.5M design limit");
        _measureBattleStage(JACKPOT_BATTLE_ENTRANTS);
    }

    /// @notice The minimum recorded pool that caps each board chip; the fixture preselects 50 distinct
    ///         wallets whose real runs all pay and receive cold FLIP credits. The field shares
    ///         one set of dice; this sample does not hit both caps for every run. Its measured
    ///         battle gas is replaced by the tested work-model allowance: the same battle is
    ///         replayed alone and its callee cost taken out before the allowance goes in.
    function test_EachStageWithMaxChipBattleFits10p5M() public {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(FullRollBudgetSeeder).runtimeCode);
        uint256 cappedBankroll = ((uint256(type(uint24).max) / 10 / 6) * 6) * 50 ether;
        uint256 cappedBudget = cappedBankroll * JACKPOT_BATTLE_ENTRANTS * 3 / 2;
        uint256 previousPool = cappedBudget * PriceLookupLib.priceForLevel(LVL) * 400 / (1000 ether);
        FullRollBudgetSeeder(payable(address(game))).setPreviousPool(LVL, previousPool);
        vm.etch(address(game), realCode);
        uint256 battleWord = _seedPayingFutureWallets(JackpotBoardFixtures.wordFor([7, 7, 7, 7], [1, 2, 3, 4], false));

        vm.recordLogs();
        game.mineFlip{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        uint256 used = _transactionGas();

        Vm.Log[] memory dailyLogs = vm.getRecordedLogs();
        uint256 dailyEthWins;
        uint256 dailyGoldenWins;
        for (uint256 i; i < dailyLogs.length; ++i) {
            assertTrue(dailyLogs[i].topics[0] != BATTLE_RUN_SIG, "battle ran in the daily transaction");
            if (dailyLogs[i].topics[0] == ETH_WIN_SIG) ++dailyEthWins;
            if (dailyLogs[i].topics[0] == keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)")) ++dailyGoldenWins;
        }
        assertEq(dailyEthWins, PURCHASE_ETH_WINNERS);
        assertEq(dailyGoldenWins, 1);
        assertTrue(game.rngLocked(), "daily stage must hold the lock for fill");
        emit log_named_uint("daily_stage_including_intrinsic", used);
        assertLt(used, 10_500_000, "daily stage exceeds design limit");

        vm.recordLogs();
        game.mineFlip{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        used = _transactionGas();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethWins;
        uint256 battleRuns;
        uint256 totalRolls;
        uint256 paidRuns;
        uint256 goldenWins;
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_WIN_SIG) ++ethWins;
            if (topic == BATTLE_RUN_SIG) {
                (,, uint256 rolls, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                ++battleRuns;
                totalRolls += rolls;
                if (paid != 0) ++paidRuns;
            }
            if (topic == keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)"))
            {
                ++goldenWins;
            }
            if (topic == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        // All 50 real runs paid distinct cold wallets, so the credits are measured at their
        // full cold-credit shape. Replace the measured dice with the tested model allowance
        // (both caps for all 50 runs, test/craps/JackpotBattle.t.sol). This is a conservative
        // composition check, not an exhaustive maximum over all words and reachable states.
        uint256 battleGas = _replayBattleGas(logs, battleWord, totalRolls, cappedBudget);
        // Also reserve the separate RIU + record path even if this sample did not qualify.
        // The production component test measures a first record, cold recipient and high-pass award.
        uint256 upperBound = used - battleGas + BATTLE_MODEL_ALLOWANCE + 400_000;
        emit log_named_uint("fill_stage_including_intrinsic", used);
        emit log_named_uint("battle_rolls_measured", totalRolls);
        emit log_named_uint("battle_gas_replayed", battleGas);
        emit log_named_uint("fill_stage_with_battle_and_award_allowances", upperBound);
        assertEq(stage, STAGE_PURCHASE_BATTLE, "purchase battle stage did not finish");
        assertEq(ethWins, 0, "ETH leg must not repeat in battle stage");
        assertEq(battleRuns, JACKPOT_BATTLE_ENTRANTS, "battle did not play all 50 wallets");
        assertEq(paidRuns, JACKPOT_BATTLE_ENTRANTS, "every run must pay its cold wallet");
        assertEq(goldenWins, 0, "golden resolution must not repeat in battle stage");
        assertLt(upperBound, 10_500_000, "fill model exceeds the 10.5M design limit");
    }

    /// @dev The battle's own gas in the measured transaction: its logged field (each wallet in
    ///      first-drawn order, repeated for its units), level and word, replayed alone at the
    ///      capped chip. The replay must throw the same rolls, which pins it to that battle.
    function _replayBattleGas(Vm.Log[] memory logs, uint256 battleWord, uint256 wantRolls, uint256 budget)
        private
        returns (uint256 g)
    {
        (address[] memory entrants, uint24 level) = _loggedField(logs);
        uint256[] memory field = JackpotBattleFieldLib.prepare(entrants, budget);
        JackpotBattleReplayMeter meter = new JackpotBattleReplayMeter();
        vm.recordLogs();
        g = meter.replay(level, field, budget, battleWord);
        assertEq(_loggedRolls(vm.getRecordedLogs()), wantRolls, "the replay is not the measured battle");
    }

    /// @dev The battle's logged field: each wallet in first-drawn order, repeated for its units.
    function _loggedField(Vm.Log[] memory logs) private pure returns (address[] memory entrants, uint24 level) {
        entrants = new address[](JACKPOT_BATTLE_ENTRANTS);
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != BATTLE_RUN_SIG) continue;
            level = uint24(uint256(logs[i].topics[1]));
            (uint256 units,,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            for (uint256 u; u < units; ++u) entrants[n++] = address(uint160(uint256(logs[i].topics[2])));
        }
        assembly ("memory-safe") {
            mstore(entrants, n)
        }
    }

    /// @dev Total dice rolls across the battle runs in `logs`.
    function _loggedRolls(Vm.Log[] memory logs) private pure returns (uint256 rolls) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != BATTLE_RUN_SIG) continue;
            (,, uint256 r,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            rolls += r;
        }
    }
}
