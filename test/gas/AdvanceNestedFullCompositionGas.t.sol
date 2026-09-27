// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CoinDrawBattle} from "../../contracts/CoinDrawBattle.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BattleRef} from "../craps/CoinDrawBattle.t.sol";
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
        lvlEntryOwner[level][pos - 1].owner = owner;
    }
}

/// @notice The costly purchase-day legs together: fresh VRF word, 365 days of failed vault
///         settlement, golden grand, redemption, 49 ETH awards, and all 50 fill-battle runs.
///         The keeper router is used to include its overhead in the measured transaction.
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
            for (uint256 seat; seat < FILL_BATTLE_ENTRANTS && pays; ++seat) {
                Craps.SlipResult memory r =
                    probe.run(battleWord, candidate, (type(uint24).max / 10 / 6) * 6, seat, FILL_BATTLE_ENTRANTS);
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

    function test_AllPurchaseDayLegsFit15M() public {
        vm.expectCall(
            ContractAddresses.WWXRP,
            abi.encodeWithSignature("mintPrize(address,uint256)", ContractAddresses.VAULT, 1 ether)
        );
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        uint256 used = beforeGas - gasleft() + INTRINSIC;

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
        assertEq(battleRuns, FILL_BATTLE_ENTRANTS, "battle did not play all 50 wallets");
        assertEq(goldenWins, 1, "golden grand was not resolved");
        emit log_named_uint("all_purchase_day_legs_including_intrinsic", used);
        assertLt(used, 15_000_000, "all composed legs exceed the 15M audit target");
    }

    /// @notice A huge recorded pool caps each board chip; the fixture preselects 50 distinct
    ///         wallets whose real runs all pay and receive cold FLIP credits. The field shares
    ///         one set of dice, which no single word throws to both caps for every run, so the
    ///         battle's measured gas is swapped for resolve's proven bound: the same battle is
    ///         replayed alone and its cost taken out of the transaction before the bound goes in.
    function test_AllLegsPlusFullBattleWorkEnvelopeFit15M() public {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(FullRollBudgetSeeder).runtimeCode);
        FullRollBudgetSeeder(payable(address(game))).setPreviousPool(LVL, 160_000_000_000_000 ether);
        vm.etch(address(game), realCode);
        uint256 battleWord = _seedPayingFutureWallets(JackpotBoardFixtures.wordFor([7, 7, 7, 7], [1, 2, 3, 4], false));

        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        uint256 used = beforeGas - gasleft() + INTRINSIC;

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
        // worst. The dice are not: take the battle's own cost out and put resolve's proven bound
        // (both caps for all 50 runs, test/craps/CoinDrawBattle.t.sol) in its place.
        uint256 battleGas = _replayBattleGas(logs, battleWord, totalRolls);
        uint256 upperBound = used - battleGas + BATTLE_PROVEN_BOUND;
        emit log_named_uint("all_legs_measured_including_intrinsic", used);
        emit log_named_uint("battle_rolls_measured", totalRolls);
        emit log_named_uint("battle_gas_replayed", battleGas);
        emit log_named_uint("all_legs_with_proven_battle", upperBound);
        assertEq(stage, STAGE_PURCHASE_DAILY, "purchase daily stage did not finish");
        assertEq(ethWins, PURCHASE_ETH_WINNERS, "ETH leg was not saturated");
        assertEq(battleRuns, FILL_BATTLE_ENTRANTS, "battle did not play all 50 wallets");
        assertEq(paidRuns, FILL_BATTLE_ENTRANTS, "every run must pay its cold wallet");
        assertEq(goldenWins, 1, "golden grand was not resolved");
        assertLt(upperBound, 15_000_000, "legs with the proven battle exceed the 15M audit target");
    }

    /// @dev The battle's own gas in the measured transaction: its logged field (each wallet in
    ///      first-drawn order, repeated for its units), level and word, replayed alone at the
    ///      capped chip. The replay must throw the same rolls, which pins it to that battle.
    function _replayBattleGas(Vm.Log[] memory logs, uint256 battleWord, uint256 wantRolls)
        private
        returns (uint256 g)
    {
        address[] memory entrants = new address[](FILL_BATTLE_ENTRANTS);
        uint256 n;
        uint24 level;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != BATTLE_RUN_SIG) continue;
            level = uint24(uint256(logs[i].topics[1]));
            (uint256 units,,,) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            for (uint256 u; u < units; ++u) entrants[n++] = address(uint160(uint256(logs[i].topics[2])));
        }
        assembly ("memory-safe") {
            mstore(entrants, n)
        }
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        g = gasleft();
        CoinDrawBattle(ContractAddresses.COIN_DRAW_BATTLE).resolve(level, entrants, 1e30, battleWord);
        g -= gasleft();
        Vm.Log[] memory replay = vm.getRecordedLogs();
        uint256 rolls;
        for (uint256 i; i < replay.length; ++i) {
            if (replay[i].topics[0] != BATTLE_RUN_SIG) continue;
            (,, uint256 r,) = abi.decode(replay[i].data, (uint256, uint256, uint256, uint256));
            rolls += r;
        }
        assertEq(rolls, wantRolls, "the replay is not the measured battle");
    }
}
