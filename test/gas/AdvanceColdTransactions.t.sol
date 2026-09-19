// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

contract ColdSubscriberSeeder is DegenerusGame {
    function useMatureLevel() external {
        level = 110;
        levelPrizePool[110] = 1000 ether;
    }

    function seedSplitBalances(address[] calldata players) external {
        for (uint256 i; i < players.length; ++i) {
            _creditClaimable(players[i], 0.001 ether + 1);
        }
        _creditClaimable(ContractAddresses.SDGNRS, 1 ether);
        claimablePool += uint128(players.length * (0.001 ether + 1) + 1 ether);
    }
}

/// @dev Setup completes before the measured transaction, including every funding/storage write.
abstract contract ColdSubscriberFixture is DeployProtocol {
    uint256 internal constant TX_CAP = 16_777_216;
    uint256 internal constant INTRINSIC = 21_064;
    bytes32 internal constant ADVANCE_EVENT = keccak256("Advance(uint8,uint24)");
    bytes32 internal constant DELIVERED_EVENT = keccak256("AfkingDelivered(address,uint256)");
    bytes32 internal constant EXPIRED_EVENT = keccak256("SubscriptionExpired(address,uint8)");
    bytes32 internal constant SKIPPED_EVENT = keccak256("PlayerSkipped(address,uint8)");

    function _mode() internal pure virtual returns (uint8);

    function _split() internal pure virtual returns (bool) {
        return false;
    }

    function _complete() internal pure virtual returns (bool) {
        return false;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 1_000_000 ether);
        vm.deal(address(this), 100_000 ether);
        _settle();

        uint8 mode = _mode();
        uint256 n = mode == 0 ? 320 : mode == 1 ? 125 : mode == 2 ? 260 : 1300;
        if (_complete()) n = mode == 1 ? 119 : 250;
        address[] memory players = new address[](n);
        for (uint256 i; i < n; ++i) {
            address player = address(uint160(0xA5700000 + i));
            players[i] = player;
            if (i < 1000) {
                _grantSeat(player);
            } else {
                _markSeatEligible(player);
                vm.prank(ContractAddresses.VAULT);
                afkingSubToken.vaultMintSeats(player, 1);
            }
            address source = _split() ? address(uint160(0xA5800000 + i)) : player;
            game.depositAfkingFunding{value: 50 ether}(source);
            if (_split()) {
                vm.prank(source);
                game.setOperatorApproval(player, true);
            }
            vm.prank(player);
            game.subscribe(address(0), _split(), mode == 1, 1, _split() ? source : address(0));
        }
        if (mode != 3) {
            game.openBoxes(2000);
        } else {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            _settle();
        }
        if (mode == 0) {
            for (uint256 i; i < n; ++i) {
                uint256 amount = game.afkingFundingOf(players[i]);
                vm.prank(players[i]);
                game.withdrawAfkingFunding(amount);
            }
        }
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ColdSubscriberSeeder).runtimeCode);
        ColdSubscriberSeeder(payable(address(game))).useMatureLevel();
        if (_split()) ColdSubscriberSeeder(payable(address(game))).seedSplitBalances(players);
        vm.etch(address(game), original);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function _settle() private {
        for (uint256 i; i < 240; ++i) {
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(id);
                if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256("cold-subscriber-setup")) | 1);
            }
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
        }
        revert("setup did not settle");
    }

    function _check(bytes32 workEvent, uint256 minimum, uint256 maximum) internal {
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: TX_CAP - INTRINSIC}();
        uint256 used = before - gasleft() + INTRINSIC;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 work;
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == workEvent) ++work;
            if (logs[i].topics[0] == ADVANCE_EVENT) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        if (_mode() == 3) {
            // Pending-box skips intentionally emit no per-player event.
            work = uint16(uint256(vm.load(address(game), bytes32(uint256(56)))));
        }
        emit log_named_uint("cold_full_advance_including_intrinsic", used);
        emit log_named_uint("completed_items", work);
        assertEq(stage, _complete() ? 1 : 11, "full subscriber chunk and expected continuation must run");
        assertGe(work, minimum, "fixture did not exercise the full chunk");
        assertLe(work, maximum, "chunk exceeded its item bound");
        assertLt(used, TX_CAP, "complete transaction exceeds cap");
    }
}

contract AdvanceColdEvictions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 0;
    }

    function test_ColdEvictionsFullTransaction() public {
        _check(EXPIRED_EVENT, 310, 313);
    }
}

contract AdvanceColdTicketSubscriptions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 1;
    }

    function test_ColdTicketsFullTransaction() public {
        _check(DELIVERED_EVENT, 117, 119);
    }
}

contract AdvanceColdLootboxSubscriptions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 2;
    }

    function test_ColdLootboxesWithStaleAffiliateCache() public {
        _check(DELIVERED_EVENT, 248, 250);
    }
}

contract AdvanceColdPendingSubscriptions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 3;
    }

    function test_ColdPendingBoxSkipsFullTransaction() public {
        _check(SKIPPED_EVENT, 1248, 1250);
    }
}

contract AdvanceColdSplitLootboxSubscriptions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 2;
    }

    function _split() internal pure override returns (bool) {
        return true;
    }

    function _complete() internal pure override returns (bool) {
        return true;
    }

    function test_ColdSplitLootboxesAndRngRequest() public {
        _check(DELIVERED_EVENT, 251, 251);
    }
}

contract AdvanceColdSplitTicketSubscriptions is ColdSubscriberFixture {
    function _mode() internal pure override returns (uint8) {
        return 1;
    }

    function _split() internal pure override returns (bool) {
        return true;
    }

    function _complete() internal pure override returns (bool) {
        return true;
    }

    function test_ColdSplitTicketsAndRngRequest() public {
        _check(DELIVERED_EVENT, 120, 120);
    }
}

contract AdvanceColdCarryover is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();
        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainTraits = JackpotBucketLib.getRandomTraits(word);
        uint8[4] memory bonusTraits =
            JackpotBucketLib.getRandomTraits(EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS"))));
        bytes memory original = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedPhaseEnd(LVL, word, mainTraits, bonusTraits, uint160(0x1000000000));
        _restore(original);
        game.advanceGame();
    }

    function test_CarryoverInItsOwnColdTransaction() public {
        vm.recordLogs();
        uint256 before = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - 21_064}();
        uint256 used = before - gasleft() + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 tickets;
        uint8 stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TICKET_WIN_SIG) ++tickets;
            if (logs[i].topics[0] == ADVANCE_SIG) (stage,) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("cold_carryover_including_intrinsic", used);
        assertEq(stage, 13, "carryover must run alone");
        assertEq(tickets, 96, "full carryover winner cap");
        assertLt(used, EIP7825_TX_GAS_CAP, "complete transaction exceeds cap");
    }
}
