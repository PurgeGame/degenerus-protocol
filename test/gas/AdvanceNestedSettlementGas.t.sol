// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {JackpotBoardFixtures} from "../fuzz/helpers/JackpotBoardFixtures.sol";
import {Vm} from "forge-std/Vm.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PurchaseDailyFixture, PurchaseDailySeeder, FreshWordLeg} from "./PurchaseDailyWorstCase.t.sol";

contract DailyGasExtrasSeeder is DegenerusGame {
    function armGolden(uint256 word) external {
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        goldenTicket = uint256(uint160(address(0xA57A))) | (uint256(traits[0] & 7) << 162)
            | (uint256(dailyIdx - 1) << 165) | (uint256(1) << 189);
    }
}

contract VaultHistorySeeder is Coinflip {
    function seedVaultHistory(bool sufficient) external {
        address player = ContractAddresses.VAULT;
        PlayerCoinflipState storage s = playerState[player];
        s.claimableStored = 0;
        s.lastClaim = 34;
        s.autoRebuyStartDay = 34;
        s.autoRebuyEnabled = true;
        s.autoRebuyStop = 1 ether;
        s.autoRebuyCarry = 0;
        for (uint24 day = 35; day <= 399; ++day) {
            _setFlipStake(day, player, sufficient ? 1000 ether : 1);
            _storeDayResult(day, 150, day != 200);
        }
    }
}

/// @dev Stress the fresh-word daily with the maximum regular historical claim window. History is
///      installed in setUp; each measured transaction begins with cold, committed slots. The word
///      applies alone (stage 18, with the vault's historical claim and any pending redemption), the
///      battle its request locked runs its own steps, then stage 6 pays the ETH leg (and an armed
///      golden ticket) and stage 15 the tickets.
abstract contract NestedSettlementFixture is PurchaseDailyFixture, FreshWordLeg {
    bytes32 internal constant GOLDEN_WIN_SIG =
        keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)");

    function _sufficient() internal pure virtual returns (bool);
    function _comps() internal pure virtual returns (bool);

    function _extras() internal pure virtual returns (bool) {
        return false;
    }

    function _router() internal pure virtual returns (bool) {
        return false;
    }

    /// @dev Runs after seeding, before the real request locks the battle's Added.
    function _beforeRequest() internal virtual {}

    function setUp() public {
        // `_comps()` = the larger recorded pool: a 26-award battle (see PurchaseDailyWorstCase).
        // `false` sits under the Added floor: a 5-award battle.
        uint256 previousPool = _comps() ? PREV_POOL_OPEN25 : PREV_POOL_FLOOR;
        uint128 nextPool = uint128(previousPool + 1 ether);
        PurchaseDailySeeder.Shape memory shape = _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, nextPool, previousPool);
        if (_extras()) {
            shape.word = JackpotBoardFixtures.wordFor([7, 7, 7, 7], [1, 2, 3, 4], false);
        }
        _seedFresh(shape);
        _beforeRequest();
        _armFreshWord(shape.word, 400);
        vm.deal(address(game), 30_000 ether);

        if (_extras()) {
            bytes memory gameCode = address(game).code;
            vm.etch(address(game), type(DailyGasExtrasSeeder).runtimeCode);
            DailyGasExtrasSeeder(payable(address(game))).armGolden(shape.word);
            vm.etch(address(game), gameCode);
            // A pending, backed 100 ETH-base gambling-redemption period.
            uint256 supplyWord = uint128(uint256(vm.load(ContractAddresses.SDGNRS, bytes32(0))));
            vm.store(
                ContractAddresses.SDGNRS,
                bytes32(0),
                bytes32(supplyWord | (uint256(175 ether) << 128) | (uint256(399) << 224))
            );
            vm.store(
                ContractAddresses.SDGNRS,
                bytes32(uint256(7)),
                bytes32(uint256(100 ether / 1 gwei) | (uint256(1e12) << 64) | (uint256(100) << 128))
            );
            vm.deal(ContractAddresses.SDGNRS, 175 ether);
        }

        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(VaultHistorySeeder).runtimeCode);
        VaultHistorySeeder(address(coinflip)).seedVaultHistory(_sufficient());
        vm.etch(address(coinflip), original);

        // Remove the vault's cheaper seat-funding routes to exercise its historical claim.
        bytes32 credits = keccak256(abi.encode(ContractAddresses.VAULT, uint256(15)));
        vm.store(address(crapsBattle), credits, bytes32(0));
        vm.store(address(crapsBattle), bytes32(uint256(16)), bytes32(0));
        uint256 supply = uint256(vm.load(address(coin), bytes32(0)));
        vm.store(address(coin), bytes32(0), bytes32(uint256(uint128(supply))));
    }

    /// @dev The word-apply transaction: the vault's 365-day claim commits or rolls back, and an
    ///      armed redemption resolves, with no daily leg.
    function _checkWordApply() internal {
        vm.expectCall(
            ContractAddresses.WWXRP,
            abi.encodeWithSignature("mintPrize(address,uint256)", ContractAddresses.VAULT, 1 ether)
        );
        (uint256 used,) = _applyWord(_router(), 10_500_000);
        bytes32 stateSlot = keccak256(abi.encode(ContractAddresses.VAULT, uint256(2)));
        uint24 settled = uint24(uint256(vm.load(address(coinflip), stateSlot)) >> 128);
        emit log_named_uint("word_apply_plus_vault_history_including_intrinsic", used);
        emit log_named_uint("vault_claim_cursor_after", settled);
        assertEq(settled, _sufficient() ? 399 : 34, "funded settlement commits; failed seat funding rolls back");
        if (_extras()) {
            assertEq(
                uint24(uint256(vm.load(ContractAddresses.SDGNRS, bytes32(0))) >> 224),
                0,
                "pending redemption must resolve"
            );
        }
    }

    /// @dev The daily stage after the battle: all 49 ETH awards, and the golden grand when armed.
    function _checkDailyStage() internal {
        (uint8 stage, uint256 used, Vm.Log[] memory logs) = _advanceTx(_router());
        uint256 goldenWins;
        bool goldenGrand;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != GOLDEN_WIN_SIG) continue;
            ++goldenWins;
            (,, goldenGrand,,,,) = abi.decode(logs[i].data, (uint8, uint8, bool, uint256, uint256, uint256, uint256));
        }
        emit log_named_uint("daily_stage_including_intrinsic", used);
        assertEq(stage, STAGE_PURCHASE_DAILY, "the daily stage follows the battle");
        assertEq(_countTopic(logs, ETH_WIN_SIG), PURCHASE_ETH_WINNERS, "all ETH awards must execute");
        assertEq(_countTopic(logs, TICKET_WIN_SIG), 0, "the ticket leg waits for its own stage");
        assertEq(_countTopic(logs, FLIP_WIN_SIG), 0, "a purchase day past level 1 runs no trait coin draw");
        assertEq(_countTopic(logs, BATTLE_ENTRY_SIG), 0, "the battle never rides the daily stage");
        assertEq(goldenWins, _extras() ? 1 : 0, "golden resolution must execute when armed");
        assertEq(goldenGrand, _extras(), "golden grand branch must execute when armed");
        assertLt(used, 10_500_000, "daily stage exceeds design limit");
    }

    function _checkNestedSettlement() internal {
        _checkWordApply();
        _driveBattle(STAGE_PURCHASE_BATTLE);
        _checkDailyStage();

        // The priced ticket leg pays from the next advance on the same recorded word.
        (uint8 stage, uint256 used, Vm.Log[] memory logs) = _advanceTx(false);
        emit log_named_uint("ticket_stage_including_intrinsic", used);
        assertEq(stage, STAGE_PURCHASE_DAILY_TICKETS, "the purchase ticket stage must follow");
        assertEq(
            _countTopic(logs, TICKET_WIN_SIG),
            PURCHASE_PHASE_TICKET_MAX_WINNERS,
            "all ticket awards must execute in the ticket stage"
        );
        assertLt(used, EIP7825_TX_GAS_CAP, "ticket stage exceeds cap");
    }
}

contract AdvanceNestedVaultSuccessfulSettlement is NestedSettlementFixture {
    function _sufficient() internal pure override returns (bool) {
        return true;
    }

    function _comps() internal pure override returns (bool) {
        return false;
    }

    function test_FullDailyWith365DayVaultSettlement() public {
        _checkNestedSettlement();
    }
}

contract AdvanceNestedVaultFailedSettlement is NestedSettlementFixture {
    function _sufficient() internal pure override returns (bool) {
        return false;
    }

    function _comps() internal pure override returns (bool) {
        return false;
    }

    function test_FullDailyWithRolledBack365DayVaultSettlement() public {
        _checkNestedSettlement();
    }
}

contract AdvanceNestedVaultCompSettlement is NestedSettlementFixture {
    function _sufficient() internal pure override returns (bool) {
        return true;
    }

    function _comps() internal pure override returns (bool) {
        return true;
    }

    function test_CompDailyWith365DayVaultSettlement() public {
        _checkNestedSettlement();
    }
}

contract AdvanceNestedDailyExtras is NestedSettlementFixture {
    function _sufficient() internal pure override returns (bool) {
        return false;
    }

    function _comps() internal pure override returns (bool) {
        return false;
    }

    function _extras() internal pure override returns (bool) {
        return true;
    }

    function test_DailyHistoryGoldenAndRedemption() public {
        _checkNestedSettlement();
    }
}

contract AdvanceNestedDailyRouter is NestedSettlementFixture {
    function _sufficient() internal pure override returns (bool) {
        return false;
    }

    function _comps() internal pure override returns (bool) {
        return false;
    }

    function _extras() internal pure override returns (bool) {
        return true;
    }

    function _router() internal pure override returns (bool) {
        return true;
    }

    function test_DailyHistoryGoldenRedemptionThroughMineFlip() public {
        _checkNestedSettlement();
    }
}
