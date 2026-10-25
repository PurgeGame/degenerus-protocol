// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeAtomicReadFixture} from "./NativeAtomicWork.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Complete prestates for the original forced winning-bet/recirculation
/// calibration. Native measurement variants change only the outcome controls.
contract ForcedBetEnvelopeGasTest is DeployProtocol, NativeGasExport {
    address private constant PLAYER = address(0xBE7CA1);

    function setUp() public {
        _deployProtocol();
        _giveWalletId(PLAYER);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 1_000_000 ether);
        vm.deal(PLAYER, 10_000 ether);
        vm.prank(address(game));
        coin.mintForGame_g152734(PLAYER, 1_000_000);
        vm.etch(address(game), type(NativeAtomicReadFixture).runtimeCode);
        NativeAtomicReadFixture(payable(address(game))).fundFuture();
    }

    function test_CompleteWinningBetCalibrationPrestates() public {
        for (uint256 shape; shape < 6; ++shape) {
            uint256 snapshot = vm.snapshotState();
            this.checkAndExport(shape);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function checkAndExport(uint256 shape) external {
        require(msg.sender == address(this), "fixture self-call");
        NativeAtomicReadFixture host = NativeAtomicReadFixture(payable(address(game)));
        uint8 currency = shape < 4 ? 0 : 1;
        uint8 spins = shape % 2 == 0 ? 1 : currency == 0 ? 25 : 15;
        uint128 stake = currency == 1 ? 100 : shape < 2 ? 1 ether : 100 ether;
        vm.prank(PLAYER);
        game.betDegenerette{value: currency == 0 ? uint256(stake) * spins : 0}(0, currency, stake, spins, 9);
        host.publishRead();
        host.setCommittedWord(0xBEEF1234); // Word 1 is the unpublished sentinel.
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        if (bytes(dir).length != 0) {
            // A naturally losing FLIP bet does not read the payout wallet. The
            // isolated dump only includes materialized backing state, so retain
            // the real registered wallet for the forced winning replay as well.
            uint32 playerId = game.walletIdOf_g3120(PLAYER);
            bytes32 playerSlot = bytes32(uint256(keccak256(abi.encode(GameSlots.WALLETS))) + playerId);
            bytes32 playerElement = vm.load(address(host), playerSlot);
            assertEq(address(uint160(uint256(playerElement))), PLAYER, "real registered payout wallet");
            vm.store(address(host), playerSlot, playerElement);
            for (uint256 i; i <= GameSlots.DEGENERETTE_QUEUE + 1; ++i) {
                bytes32 slot = bytes32(i);
                vm.store(address(host), slot, vm.load(address(host), slot));
            }
            address[11] memory accounts = [address(coinflip), address(coin), address(sdgnrs),
                address(wwxrp), address(crapsBattle), address(vault), address(gnrus),
                ContractAddresses.RECORD_BOUNTY, ContractAddresses.DEITY_PASS,
                ContractAddresses.QUESTS, ContractAddresses.AFFILIATE];
            for (uint256 a; a < accounts.length; ++a) {
                vm.etch(accounts[a], accounts[a].code);
                for (uint256 i; i < 32; ++i) {
                    bytes32 slot = bytes32(i);
                    vm.store(accounts[a], slot, vm.load(accounts[a], slot));
                }
            }
            // A forced recirculation can reach workers skipped by the natural
            // fixture roll. Preserve their actual deployed code in the world dump.
            address[19] memory modules = [
                ContractAddresses.GAME_ACTIONS_MODULE,
                ContractAddresses.GAME_PURCHASE_MODULE,
                ContractAddresses.GAME_MINT_MODULE,
                ContractAddresses.GAME_DEGENESIS_MODULE,
                ContractAddresses.GAME_ADVANCE_MODULE,
                ContractAddresses.GAME_RNG_MODULE,
                ContractAddresses.GAME_JACKPOT_MODULE,
                ContractAddresses.GAME_JACKPOT_DRAW_MODULE,
                ContractAddresses.GAME_WHALE_MODULE,
                ContractAddresses.GAME_TICKET_MODULE,
                ContractAddresses.GAME_LOOTBOX_MODULE,
                ContractAddresses.GAME_BOON_MODULE,
                ContractAddresses.GAME_DEGENERETTE_MODULE,
                ContractAddresses.GAME_AFKING_MODULE,
                ContractAddresses.GAME_GAMEOVER_MODULE,
                ContractAddresses.GAME_DECIMATOR_MODULE,
                ContractAddresses.GAME_MINER_MODULE,
                ContractAddresses.CRAPS_ENGINE,
                ContractAddresses.CRAPS_LIFECYCLE_MODULE
            ];
            for (uint256 i; i < modules.length; ++i) vm.etch(modules[i], modules[i].code);
            // Separate profile roots may be reached only by a forced boon branch.
            // Export their actual namespace headers even when the natural roll skipped them.
            bytes32[2] memory roots = [
                bytes32(0x04343aaa474371a66bb47cad27e6432f6ed56b02c7b23c6e11e4d1818f7af200),
                bytes32(0x93b2738aa52d403a1d6cd7cad14e72a7cda308b6a92d312ff0746cbfb7eec800)
            ];
            for (uint256 a; a < 2; ++a) {
                address owner = a == 0 ? ContractAddresses.QUESTS : ContractAddresses.AFFILIATE;
                for (uint256 i; i < 8; ++i) {
                    bytes32 slot = bytes32(uint256(roots[a]) + i);
                    vm.store(owner, slot, vm.load(owner, slot));
                }
            }
            string memory label = string.concat("bet-forced-prestate-", vm.toString(shape));
            vm.dumpState(string.concat(dir, "/", label, ".complete.json"));
            vm.serializeUint(label, "currency", currency);
            vm.serializeUint(label, "spins", spins);
            vm.serializeUint(label, "stake", stake);
            vm.serializeBool(label, "record", (host.bet() >> 43) & 1 != 0);
            this.exportNativeFixture(label, address(this), address(host), abi.encodeCall(host.workBet, (uint256(14_000_000))));
        }
        MineFlipGas.Result memory result = host.workBet(14_000_000);
        assertTrue(result.done, "the full immutable bet executes");
        assertEq(result.rewardBasis, 1, "one completed bet");
        assertEq(host.betCursor(), 1, "the atomic cursor commits");
    }
}
