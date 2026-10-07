// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title AccountRuleBafSettle -- the BAF-level seal settles the vault's coinflips by ID
/// @notice At an x0 level's last-purchase-day seal the advance calls
///         `coinflip.depositCoinflip(VAULT_WALLET_ID = 1, 0)`. Coinflip resolves ID 1 through
///         `Game.resolveAccount(1, GAME)`: unapproved, the zero-amount call is a gift that only
///         settles the vault's own claims; approved (`operatorApprovals[1][GAME]`), it is an
///         authorized zero deposit. Either way the advance must not revert. The drive turbo-chains
///         from genesis to the level-10 latch day (the shape of TurboBafTicketFloor's drive).
contract AccountRuleBafSettle is DeployProtocol {
    bytes32 private constant COINFLIP_DEPOSIT = keccak256("CoinflipDeposit(address,uint256)");

    address private buyer = address(0xBA5E1);
    uint256 private simTime;
    uint256 private vaultSettles;

    function setUp() public {
        _deployProtocol();
        simTime = block.timestamp + 1 days + 1;
        vm.warp(simTime);
        vm.deal(address(game), 10_000 ether);
        vm.deal(buyer, 500_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    function test_BafSeal_SettlesVaultById_Unapproved() public {
        (, , bool authorized) = game.resolveAccount(1, address(game));
        assertFalse(authorized, "fixture: GAME is not an operator of the vault's account");
        _driveAndAssert();
    }

    function test_BafSeal_SettlesVaultById_GameApprovedForVault() public {
        bytes32 slot = keccak256(abi.encode(address(game), keccak256(abi.encode(uint256(1), GameSlots.OPERATOR_APPROVALS))));
        vm.store(address(game), slot, bytes32(uint256(1)));
        (address key, address payee, bool authorized) = game.resolveAccount(1, address(game));
        assertTrue(authorized, "fixture: operatorApprovals[1][GAME] set");
        assertEq(key, ContractAddresses.VAULT);
        assertEq(payee, ContractAddresses.VAULT);
        _driveAndAssert();
    }

    function _driveAndAssert() private {
        vm.pauseGasMetering();
        vm.expectCall(
            address(coinflip), abi.encodeWithSignature("depositCoinflip(uint32,uint256)", uint32(1), uint256(0)), 1
        );
        vm.expectCall(address(game), abi.encodeCall(game.resolveAccount, (uint32(1), address(game))));
        _driveToLevelTenLatchDay();
        assertEq(vaultSettles, 1, "one zero-amount vault settle, at the level-10 seal");
        (uint24 lvl, , bool lpd, , ) = game.purchaseInfo();
        assertEq(lvl, 9);
        assertTrue(lpd, "the x0 seal ran");
    }

    // ---------------------------------------------------------------------
    // Drive
    // ---------------------------------------------------------------------

    function _driveToLevelTenLatchDay() private {
        _settleToday();
        for (uint256 i = 0; i < 120; i++) {
            require(!game.gameOver(), "harness: gameOver before the level-10 latch");
            (uint24 lvl, , bool lastPurchaseDay_, , ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == 9) return;
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(_levelPrizePool(_level()) + 25 ether);
                _buyTickets();
            }
            vm.recordLogs();
            _runFullDayUntilX0Latch();
            _countVaultSettles(vm.getRecordedLogs());
        }
        revert("harness: never reached the level-10 latch day");
    }

    function _countVaultSettles(Vm.Log[] memory logs) private {
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(coinflip) || logs[j].topics.length < 2) continue;
            if (logs[j].topics[0] != COINFLIP_DEPOSIT) continue;
            if (address(uint160(uint256(logs[j].topics[1]))) != ContractAddresses.VAULT) continue;
            if (abi.decode(logs[j].data, (uint256)) == 0) ++vaultSettles;
        }
    }

    function _runFullDayUntilX0Latch() private {
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            if (!_mine()) break;
            (uint24 lvl, , bool lastPurchaseDay_, bool locked, ) = game.purchaseInfo();
            if (lastPurchaseDay_ && lvl == 9 && (!locked || (_jackpotFlags() == 1 && _requestInFlight()))) break;
        }
    }

    function _settleToday() private {
        for (uint256 i = 0; i < 300; i++) {
            _fulfillPending();
            if (!_mine()) break;
        }
    }

    function _mine() private returns (bool) {
        if (game.nextMinerAction() == uint8(DegenerusGameStorage.MinerAction.RequestMidday)) return false;
        uint256[6] memory ladder = [uint256(1_500_000), 2_500_000, 3_500_000, 5_000_000, 9_000_000, 16_777_216];
        for (uint256 r; r < ladder.length; ++r) {
            (bool ok, bytes memory err) = address(game).call{gas: ladder[r]}(abi.encodeWithSignature("mineFlip()"));
            if (ok) return true;
            if (bytes4(err) != MineFlipGas.InsufficientExecutionGas.selector) return false;
        }
        return false;
    }

    function _requestInFlight() private view returns (bool) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (, , bool fulfilled) = mockVRF.pendingRequests(id);
        return !fulfilled;
    }

    function _fulfillPending() private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId))) | 1;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _buyTickets() private {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        vm.prank(buyer);
        game.purchase{value: (priceWei * 4000) / 400}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _seedNextPrizePool(uint256 targetNext) private {
        bytes32 slot = bytes32(GameSlots.PRIZE_POOLS_PACKED);
        uint256 packed = uint256(vm.load(address(game), slot));
        if ((packed & type(uint128).max) >= targetNext) return;
        vm.store(address(game), slot, bytes32(((packed >> 128) << 128) | targetNext));
    }

    function _levelPrizePool(uint24 lvl) private view returns (uint256) {
        uint256 v = uint256(vm.load(address(game), keccak256(abi.encode(uint256(lvl), GameSlots.LEVEL_PRIZE_POOL))));
        return v < 50 ether ? 50 ether : v;
    }

    function _level() private view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(GameSlots.LEVEL)))) >> (GameSlots.LEVEL_OFFSET * 8));
    }

    function _jackpotFlags() private view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(GameSlots.JACKPOT_FLAGS)))) >> (GameSlots.JACKPOT_FLAGS_OFFSET * 8));
    }
}
