// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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
        uint256 previousPool = _comps() ? PREV_POOL_COMP : PREV_POOL;
        uint128 nextPool = uint128(previousPool + 1 ether);
        PurchaseDailySeeder.Shape memory shape = _shape(MAIN_HOLDERS, BONUS_HOLDERS, FF_HOLDERS, nextPool, previousPool);
        if (_extras()) {
            shape.word |= (uint256(0x38)) | (uint256(0x38) << 6) | (uint256(0x38) << 12) | (uint256(0x38) << 18);
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
            if (topic == COMP_WIN_SIG) ++compWins;
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
        emit log_named_uint("near_FLIP_awards", nearWins);
        emit log_named_uint("far_FLIP_awards", farWins);
        assertEq(stage, STAGE_PURCHASE_DAILY, "daily must finish in the RNG-apply transaction");
        assertEq(ethWins, PURCHASE_ETH_WINNERS, "all ETH awards must execute");
        assertEq(ticketWins, PURCHASE_PHASE_TICKET_MAX_WINNERS, "all ticket awards must execute");
        assertEq(compWins, _comps() ? 6 : 0, "expected coin jackpot branch must execute");
        assertEq(goldenWins, _extras() ? 1 : 0, "golden resolution must execute when armed");
        assertEq(goldenGrand, _extras(), "golden grand branch must execute when armed");
        if (_comps()) assertGe(nearWins, 37, "full near draw less the comp quadrant");
        else assertEq(nearWins, 50, "all near FLIP draws must execute");
        assertEq(farWins, 8, "all far FLIP draws must execute");
        if (_extras()) {
            assertEq(
                uint24(uint256(vm.load(ContractAddresses.SDGNRS, bytes32(0))) >> 224),
                0,
                "pending redemption must resolve"
            );
        }
        assertEq(settled, _sufficient() ? 399 : 34, "funded settlement commits; failed seat funding rolls back");
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
