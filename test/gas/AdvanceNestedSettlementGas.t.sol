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

/// @dev Stress the complete daily call with the maximum regular historical claim window.
///      History is installed in setUp; the measured transaction begins with cold, committed slots.
abstract contract NestedSettlementFixture is PurchaseDailyFixture, FreshWordLeg {
    function _sufficient() internal pure virtual returns (bool);
    function _comps() internal pure virtual returns (bool);

    function _extras() internal pure virtual returns (bool) {
        return false;
    }

    function _router() internal pure virtual returns (bool) {
        return false;
    }

    function setUp() public {
        // `_comps()` = the heaviest coin budget: 25 opener seats (see PurchaseDailyWorstCase).
        uint256 previousPool = _comps() ? PREV_POOL_OPEN25 : PREV_POOL;
        uint128 nextPool = uint128(previousPool + 1 ether);
        PurchaseDailySeeder.Shape memory shape = _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, nextPool, previousPool);
        if (_extras()) {
            shape.word = JackpotBoardFixtures.wordFor([7, 7, 7, 7], [1, 2, 3, 4], false);
        }
        _seedFresh(shape);
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
                keccak256(abi.encode(uint256(399), uint256(7))),
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

    function _checkNestedSettlement() internal {
        vm.expectCall(
            ContractAddresses.WWXRP,
            abi.encodeWithSignature("mintPrize(address,uint256)", ContractAddresses.VAULT, 1 ether)
        );
        vm.recordLogs();
        uint256 before = gasleft();
        if (_router()) game.mineFlip{gas: EIP7825_TX_GAS_CAP - 21_064}();
        else game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ethWins;
        uint256 ticketWins;
        uint256 compWins;
        uint256 goldenWins;
        uint256 nearWins;
        uint256 farWins;
        bool goldenGrand;
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_WIN_SIG) ++ethWins;
            if (topic == TICKET_WIN_SIG) ++ticketWins;
            if (topic == CRAPS_WIN_SIG) ++compWins;
            if (topic == FLIP_WIN_SIG) ++nearWins;
            if (topic == FAR_WIN_SIG) ++farWins;
            if (topic == keccak256("GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)"))
            {
                ++goldenWins;
                (,, goldenGrand,,,,) =
                    abi.decode(logs[i].data, (uint8, uint8, bool, uint256, uint256, uint256, uint256));
            }
            if (topic == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        bytes32 stateSlot = keccak256(abi.encode(ContractAddresses.VAULT, uint256(2)));
        uint24 settled = uint24(uint256(vm.load(address(coinflip), stateSlot)) >> 128);
        emit log_named_uint("full_daily_plus_vault_history_including_intrinsic", used);
        emit log_named_uint("vault_claim_cursor_after", settled);
        emit log_named_uint("trait_FLIP_awards", nearWins);
        emit log_named_uint("fill_FLIP_awards", farWins);
        emit log_named_uint("craps_seat_awards", compWins);
        assertEq(stage, STAGE_PURCHASE_DAILY, "daily must finish in the RNG-apply transaction");
        assertEq(ethWins, PURCHASE_ETH_WINNERS, "all ETH awards must execute");
        assertEq(ticketWins, 0, "the ticket leg waits for its own stage");
        // The purchase coin draw is the fill draw alone: 13 opener seats at PREV_POOL (B 62,500),
        // 25 at PREV_POOL_OPEN25, and 25 equal coin shares either way.
        assertEq(compWins, _comps() ? 25 : 13, "the craps half must seat every pull");
        assertEq(goldenWins, _extras() ? 1 : 0, "golden resolution must execute when armed");
        assertEq(goldenGrand, _extras(), "golden grand branch must execute when armed");
        assertEq(nearWins, 0, "a purchase day past level 1 runs no trait coin draw");
        assertEq(farWins, 25, "all 25 coin shares must execute");
        if (_extras()) {
            assertEq(
                uint24(uint256(vm.load(ContractAddresses.SDGNRS, bytes32(0))) >> 224),
                0,
                "pending redemption must resolve"
            );
        }
        assertEq(settled, _sufficient() ? 399 : 34, "funded settlement commits; failed seat funding rolls back");

        // The priced ticket leg pays from the next advance on the same recorded word.
        vm.recordLogs();
        before = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        used = before - gasleft() + 21_064;
        logs = vm.getRecordedLogs();
        ticketWins = 0;
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TICKET_WIN_SIG) ++ticketWins;
            if (logs[i].topics[0] == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("ticket_stage_including_intrinsic", used);
        assertEq(stage, 15, "the purchase ticket stage must follow");
        assertEq(ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "all ticket awards must execute in the ticket stage");
        assertLt(used, EIP7825_TX_GAS_CAP, "ticket stage exceeds cap");
        assertLt(used, EIP7825_TX_GAS_CAP, "complete transaction exceeds cap");
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
