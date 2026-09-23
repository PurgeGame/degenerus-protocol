// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";
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
    function _seedPayingFutureWallets(uint256 dailyWord) private {
        uint24 purchaseLevel = LVL + 1;
        uint256 battleWord = uint256(keccak256(abi.encode(dailyWord, purchaseLevel, keccak256("far-future-coin"))));
        BattleRef probe = new BattleRef();
        address[56] memory paying;
        uint256 found;
        for (uint160 n = 1; found < paying.length && n < 100_000; ++n) {
            address candidate = address(uint160(0x5000000000) + n);
            Craps.SlipResult memory r = probe.run(battleWord, candidate, type(uint24).max / 10);
            if (r.totalRolls == 200) {
                paying[found++] = candidate;
            }
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
    ///         wallets whose real runs all reach the exact 200-roll cap and receive cold FLIP
    ///         credits. The bound then adds the complete 22-hand allowance per run, deliberately
    ///         counting hand work the measured transaction already did twice.
    function test_AllLegsPlusFullBattleWorkEnvelopeFit15M() public {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(FullRollBudgetSeeder).runtimeCode);
        FullRollBudgetSeeder(payable(address(game))).setPreviousPool(LVL, 160_000_000_000_000 ether);
        vm.etch(address(game), realCode);
        _seedPayingFutureWallets(JackpotBoardFixtures.wordFor([7, 7, 7, 7], [1, 2, 3, 4], false));

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
        // All 50 real runs reached the 200-roll cap and credited distinct cold wallets.
        // Add the entire 22-hand allowance for each run to cover even the most expensive
        // possible shooter breakdown of those same 10,000 rolls; the measured runs already
        // consumed some hands, so this deliberately counts their hand work twice.
        uint256 upperBound = used + FILL_BATTLE_ENTRANTS * 1100 * 22;
        emit log_named_uint("all_legs_measured_including_intrinsic", used);
        emit log_named_uint("battle_rolls_measured", totalRolls);
        emit log_named_uint("all_legs_plus_full_hand_envelope", upperBound);
        assertEq(stage, STAGE_PURCHASE_DAILY, "purchase daily stage did not finish");
        assertEq(ethWins, PURCHASE_ETH_WINNERS, "ETH leg was not saturated");
        assertEq(battleRuns, FILL_BATTLE_ENTRANTS, "battle did not play all 50 wallets");
        assertEq(totalRolls, FILL_BATTLE_ENTRANTS * 200, "not every run reached the roll cap");
        assertEq(paidRuns, FILL_BATTLE_ENTRANTS, "every run must pay its cold wallet");
        assertEq(goldenWins, 1, "golden grand was not resolved");
        assertLt(upperBound, 15_000_000, "full hand envelope exceeds the 15M audit target");
    }
}
