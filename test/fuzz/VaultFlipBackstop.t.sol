// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Seed only the committed phase preconditions. Settlement and callbacks are production code.
contract VaultBackstopHost is DegenerusGame {
    function seedPhase(uint24 day, uint24 stamp, uint8 mode) external {
        vaultFlipSettledDay = stamp;
        dailyIdx = day;
        dailyComplete = false;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay();
        rngRequestDay = day;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 123;
        rngLockedFlag = true;
        ticketsFullyProcessed = true;
        _setRngRequest(vrfRequestId == 0 ? 1 : vrfRequestId);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        _recordDailyRng(day, 123);
        level = mode == 0 ? 0 : mode == 1 ? 9 : 10;
        lastPurchaseDay = mode == 1;
        jackpotPhaseFlag = mode >= 2;
        phaseTransitionActive = mode == 3;
    }

    function stamp() external view returns (uint24) { return vaultFlipSettledDay; }

    function phase(uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runDailyPhase_g2582(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
}

contract VaultBackstopSeeder is CoinflipStakeSetter {
    function seed(uint24 day, uint24 gap) external {
        playerState[1].lastClaim = day - gap;
        for (uint256 d = day - gap + 1; d <= day; ++d) {
            _setFlipStake(uint24(d), 1, 5000);
            _storeDayResult(uint24(d), 150, true);
        }
        flipsClaimableDay = day;
    }
}

contract VaultFlipBackstopTest is DeployProtocol {
    VaultBackstopHost private host;
    uint24 private constant DAY = 180;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(VaultBackstopHost).runtimeCode);
        host = VaultBackstopHost(payable(address(game)));
        vm.warp((uint256(DAY - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _seed(uint24 gap, uint24 stamp, uint8 mode) private {
        host.seedPhase(DAY, stamp, mode);
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(VaultBackstopSeeder).runtimeCode);
        VaultBackstopSeeder(address(coinflip)).seed(DAY, gap);
        vm.etch(address(coinflip), code);
    }

    function _position() private view returns (uint128 bank, uint24 cursor) {
        uint256 w = uint256(vm.load(address(coinflip), keccak256(abi.encode(uint256(1), uint256(2)))));
        return (uint128(w), uint24(w >> 128));
    }

    function test_checkpointPrecedesEveryDailyBranchAndBanksExactlyOnce() public {
        for (uint8 mode; mode < 4; ++mode) {
            uint256 snapshot = vm.snapshotState();
            _seed(45, DAY - 45, mode);
            uint256 allowanceBefore = coin.vaultMintAllowance();
            bytes32 packedBefore = vm.load(address(game), bytes32(GameSlots.RNG_REQUEST_DAY));
            MineFlipGas.Result memory r = host.phase(9_000_000);
            assertTrue(r.progressed);
            assertFalse(r.done, "settlement is its own checkpoint");
            assertTrue(game.rngLocked(), "later phases retain the lock");
            assertEq(host.stamp(), DAY);
            uint256 stampMask = uint256(type(uint24).max) << 160;
            assertEq(uint256(vm.load(address(game), bytes32(GameSlots.RNG_REQUEST_DAY))) & ~stampMask,
                uint256(packedBefore) & ~stampMask, "packed RNG and loan fields preserved");
            (uint128 bank, uint24 cursor) = _position();
            assertEq(bank, 45 * 12_500);
            assertEq(cursor, DAY);
            assertEq(coin.vaultMintAllowance(), allowanceBefore, "zero deposit banks without minting");
            // A later direct settle cannot duplicate the bank, or alter the Game stamp.
            vm.prank(ContractAddresses.GAME);
            coinflip.depositCoinflip(1, 0);
            (uint128 afterBank,) = _position();
            assertEq(afterBank, bank);
            assertEq(host.stamp(), DAY);
            vm.revertToState(snapshot);
        }
    }

    function test_lowContinuationRefusesWithoutUpdatingStampButFirstUnitCanRun() public {
        _seed(45, DAY - 45, 0);
        MineFlipGas.Result memory refused = host.phase(MineFlipGas.budget(500_000, 10_000, false));
        assertFalse(refused.progressed);
        assertEq(host.stamp(), DAY - 45);
        (, uint24 cursor) = _position();
        assertEq(cursor, DAY - 45);
        MineFlipGas.Result memory first = host.phase(MineFlipGas.budget(500_000, 10_000, true));
        assertTrue(first.progressed);
        assertEq(host.stamp(), DAY);
    }

    function test_externalSettleLeavesOwnStampAndDueCheckpointIsSafeRedundancy() public {
        _seed(76, DAY - 76, 0);
        vm.prank(ContractAddresses.VAULT);
        coinflip.depositCoinflip(0, 0);
        (uint128 bank,) = _position();
        assertEq(bank, 76 * 12_500, "44 + 31 + 1 recovery backlog retained");
        assertEq(host.stamp(), DAY - 76);
        assertTrue(host.phase(9_000_000).progressed);
        (uint128 afterBank,) = _position();
        assertEq(afterBank, bank);
        assertEq(host.stamp(), DAY);
    }

    function test_failedSettleRollsBackStampAndCursor() public {
        _seed(90, DAY - 90, 0);
        vm.mockCallRevert(ContractAddresses.JACKPOTS,
            abi.encodeWithSignature("recordBafFlip(uint32,uint24,uint256)"), abi.encodeWithSignature("TestFailure()"));
        vm.expectRevert(bytes4(keccak256("TestFailure()")));
        host.phase(9_000_000);
        assertEq(host.stamp(), DAY - 90);
        (uint128 bank, uint24 cursor) = _position();
        assertEq(bank, 0);
        assertEq(cursor, DAY - 90);
        vm.clearMockedCalls();
        assertTrue(host.phase(9_000_000).progressed);
        (bank, cursor) = _position();
        assertEq(bank, 90 * 12_500);
        assertEq(cursor, DAY);
    }
}
