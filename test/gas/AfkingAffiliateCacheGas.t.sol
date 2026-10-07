// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract AfkingAffiliateCacheHost is DegenerusGame, WalletSeed {
    function prepare(address player, bool cacheHit) external {
        uint24 today = _simulatedDayIndex();
        uint32 id = _seedWallet(player);
        level = 24;
        dailyIdx = today - 1;
        _afkingResetDay = today;
        _subCursor = 0;
        _subOpenCursor = 0;
        _pendingBoxCount = 0;
        delete _subscribers;
        _subscribers.push(uint256(uint160(player)) | (uint256(id) << 160));
        subsFullyProcessed = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        _sdgnrsBonusLevel = level;
        // A pass/seat holder with actual prior purchases. The prior level's cache
        // is stale on the first buy after24; a subsequent buy already has tag24.
        mintPacked_[player] |= uint256(23) | (uint256(10) << 24)
            | (uint256(today - 1) << BitPackingLib.DAY_SHIFT)
            | (uint256(cacheHit ? 24 : 23) << BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT);
        Sub storage sub = _subOf[id];
        sub.setPosition = 1;
        sub.dailyQuantity = 255;
        sub.flags = 0;
        sub.lastAutoBoughtDay = today - 1;
        sub.lastOpenedDay = today - 1;
        sub.afkingStartDay = today - 1;
        sub.afkCoveredThroughDay = today - 1;
        _creditAfkingValue(id, 100 ether);
    }

    function buy() external returns (MineFlipGas.Result memory result) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runSubscriberWork(uint24,uint256)", _afkingResetDay, uint256(12_000_000))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    function pending() external view returns (uint256) { return _pendingBoxCount; }
    function bought(address player) external view returns (uint24) { return _subOf[_walletIdOf(player)].lastAutoBoughtDay; }
}

contract AfkingAffiliateCacheGasTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    AfkingAffiliateCacheHost private host;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        _grantSeat(PLAYER);
        vm.etch(address(game), type(AfkingAffiliateCacheHost).runtimeCode);
        host = AfkingAffiliateCacheHost(payable(address(game)));
        vm.deal(address(game), 1_000 ether);
        if (vm.envOr("AFKING_UPDATE_USE_BASELINE", false)) {
            string memory path = vm.envString("AFKING_UPDATE_BASELINE_FILE");
            vm.etch(address(afkingModule), vm.parseJsonBytes(vm.readFile(path), ".runtime"));
        }
    }

    function _measure(bool cacheHit) private {
        host.prepare(PLAYER, cacheHit);
        MineFlipGas.Result memory result = host.buy{gas: 12_000_000}();
        uint256 used = vm.snapshotGasLastCall("afking-affiliate-cache", cacheHit ? "auto_box_cache_hit" : "auto_box_level_refresh");
        uint256 bound = GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS;
        emit log_named_string("scenario", cacheHit ? "auto_box_cache_hit" : "auto_box_level_refresh");
        emit log_named_uint("execution_gas", used);
        emit log_named_uint("worker_item_and_tail_bound", bound);
        emit log_named_uint("margin", bound - used);
        assertTrue(result.progressed && result.done);
        assertEq(result.rewardBasis, 1);
        assertEq(host.pending(), 1);
        assertEq(host.bought(PLAYER), game.currentDayView());
        assertLe(used, bound, "cold durable-history box buy exceeds worker envelope");
    }

    function testGas_AutoBoxAfterLevelAdvance() public { _measure(false); }
    function testGas_AutoBoxLaterAtSameLevel() public { _measure(true); }
}
