// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract StorageReuseAtomicHost is DegenerusGame {
    function seed(uint24 day, bool terminal) external {
        level = 10;
        dailyIdx = day;
        purchaseStartDay = terminal ? 1 : day - 1;
        rngRequestDay = day;
        rngRequestTime = uint48(block.timestamp);
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
        rngWordCurrent = 987654321;
        rngLockedFlag = true;
        ticketsFullyProcessed = true;
        _setRngRequestActive(true);
        // A terminal callback has arrived but publication belongs to its apply.
        _setRngSessionPublished(!terminal);
        _setRngComplete(false);
        if (terminal) {
            _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
            _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
            _setRngTerminal();
        }
    }

    function atomic(bool terminal) external returns (bytes memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(terminal
            ? abi.encodeWithSignature("runTerminalPhase(uint256)", uint256(9_000_000))
            : abi.encodeWithSignature("applyDailyWord_g1652()"));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return data;
    }
}

contract StorageReuseNativeAtomicTest is DeployProtocol, NativeGasExport {
    function _prepare(bool terminal) private {
        _deployProtocol();
        uint24 day = 21_000;
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.etch(address(game), type(StorageReuseAtomicHost).runtimeCode);
        StorageReuseAtomicHost(payable(address(game))).seed(day, terminal);
        // Establish the prior frontier through the production resolver: sDGNRS's
        // cursor and perpetual-rebuy latch must agree with a mature resolved day.
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, 2, day - 1);
    }

    function _verifyApplied(bool terminal) private {
        StorageReuseAtomicHost(payable(address(game))).atomic(terminal);
        // Terminal entropy is published without settling another worthless FLIP round.
        uint24 last = terminal ? 20_999 : 21_000;
        assertEq(uint24(uint256(vm.load(address(coinflip), bytes32(uint256(4))))), last);
        bytes32 vaultState = keccak256(abi.encode(uint256(1), uint256(2)));
        assertEq(uint24(uint256(vm.load(address(coinflip), vaultState)) >> 128), 0, "no Vault claim in RNG work");
        assertEq(uint24(uint256(vm.load(address(game), bytes32(uint256(5)))) >> 160), 0, "no backstop stamp");
        if (terminal) assertEq(game.rngWordForDay(21_000), 987654321, "terminal word actually applied");
    }

    function test_nativeDailyApplyWithoutVaultBackstop() public {
        _prepare(false);
        _nativeFixture("daily_apply_logical", address(0x8888), address(game), abi.encodeCall(StorageReuseAtomicHost.atomic, (false)));
        _verifyApplied(false);
    }

    function test_nativeTerminalApplyWithoutVaultBackstop() public {
        _prepare(true);
        _nativeFixture("terminal_apply_logical", address(0x8888), address(game), abi.encodeCall(StorageReuseAtomicHost.atomic, (true)));
        _verifyApplied(true);
    }
}
