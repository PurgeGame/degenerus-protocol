// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {Vm} from "forge-std/Vm.sol";

contract HumanOrderGasSeed is DegenerusGame {
    function seedOrder(address player, uint256 input, uint256 coverWei, bool presale, uint256 entropy) external {
        level = 99;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        _afkingResetDay = dailyIdx;
        subsFullyProcessed = true;
        _setRngRequestActive(false);
        _setRngComplete(false);
        _setRngSessionPublished(true);
        rngLockedFlag = false;
        rngWordCurrent = entropy;
        ticketsFullyProcessed = true;
        humanReadComplete = false;
        _pendingBoxCount = 0;
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 0);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        uint48 idx = _rngReadBuffer();
        uint256 word = uint256(100) | uint256(ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) << LB_SCORE_SHIFT
            | (input & 0xff) << LB_SMALL_SHIFT
            | ((input >> 8) & 0xff) << LB_MED_SHIFT
            | ((input >> 16) & 0xff) << LB_LARGE_SHIFT
            | ((input >> 24) & 0xff) << LB_CUSTOM_COUNT_SHIFT
            | ((input >> 32) & LB_CUSTOM_SIZE_MASK) << LB_CUSTOM_SIZE_SHIFT
            | (coverWei / LB_CUSTOM_SCALE) << LB_COVER_SHIFT;
        uint256 nominal = BoxOrderLib.boNominal(word, PriceLookupLib.priceForLevel(100));
        uint256 eligible = nominal < LOOTBOX_EV_BENEFIT_CAP ? nominal : LOOTBOX_EV_BENEFIT_CAP;
        word |= (eligible * 10_000 / nominal) << LB_ADJ_SHIFT;
        lootboxOrder[idx][player] = word;
        delete boxPlayers[idx];
        boxPlayers[idx].push(player);
        if (presale) {
            presaleBoxEth[idx][player] = 50 ether | PRESALE_BOX_CLOSING_FLAG;
            presaleBoxEthSold = 50 ether;
            presaleOver = true;
            presaleDrained = false;
            presaleCloser = player;
            presaleCloseBuffer = idx;
        } else presaleDrained = true;
        _setCurrentPrizePool(10_000 ether);
        _setPrizePools(10_000 ether, 10_000 ether);
    }

    function rawAtomic(address player) external returns (uint256 boxes) {
        uint48 idx = _rngReadBuffer();
        uint256 word = _boxOrder(idx, player);
        boxes = _boxOrderCount(word);
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature("resolveHumanBoxOrder(address,uint48,uint256,uint256,uint256,uint24)",
                player, idx, word, presaleBoxEth[idx][player], _lootboxWord(idx), level + 1)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    function orderLeft(address player) external view returns (uint256) {
        return _boxOrder(_rngReadBuffer(), player);
    }

    function outcome(address player) external view returns (bytes32 digest) {
        digest = keccak256(abi.encode(_claimableOf(player), boonPacked[player], mintPacked_[player],
            _getCurrentPrizePool(), _getNextPrizePool(), _getFuturePrizePool(),
            presaleDrained, humanReadComplete, _boxOrder(_rngReadBuffer(), player)));
        for (uint24 lvl = 100; lvl <= 150; ++lvl) {
            digest = keccak256(abi.encode(digest, _entriesOwedTotal(lvl, player)));
        }
    }
}

contract HumanOrderNativeGasTest is DeployProtocol {
    address private constant PLAYER = address(0xB0A100);
    address private constant MINER = address(0xB0A200);
    bytes private gameCode;
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant MINER_BOUNTY = keccak256("MinerBounty(uint8,address,uint256)");

    function setUp() public {
        _deployProtocol(false);
        gameCode = address(game).code;
        vm.deal(address(game), 50_000 ether);
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
    }

    function _cool() private {
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(address(sdgnrs)); vm.cool(address(wwxrp)); vm.cool(address(crapsBattle));
        vm.cool(ContractAddresses.GAME_MINER_MODULE); vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE); vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE); vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
    }

    function _probe(uint256 input, uint256 cover, bool presale, uint256 word) private {
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        host.seedOrder(PLAYER, input, cover, presale, word);
        uint256 snapshot = vm.snapshotState();
        uint256 count = BoxOrderLib.boCount(host.orderLeft(PLAYER));
        uint256 bound = GasBounds.HUMAN_ENTRY_GAS + count * GasBounds.HUMAN_BOX_GAS
            + (presale ? GasBounds.HUMAN_PRESALE_GAS : 0);
        _cool();
        uint256 beforeGas = gasleft();
        uint256 resolved = host.rawAtomic{gas: 25_000_000}(PLAYER);
        uint256 atomicGas = beforeGas - gasleft();
        emit log_named_uint("human boxes", resolved);
        emit log_named_uint("cold full atomic human order gas", atomicGas);
        emit log_named_uint("configured atomic human allowance", bound);
        assertEq(resolved, count);
        assertEq(host.orderLeft(PLAYER), 0);
        assertLe(atomicGas, 10_000_000, "one indivisible order exceeds checkpoint-step maximum");
        assertTrue(vm.revertToState(snapshot));
        vm.etch(address(game), gameCode);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.HumanBoxes), "real engine must select human FIFO");
        snapshot = vm.snapshotState();
        bytes32 full = _mineAndReadOutcome();
        assertTrue(vm.revertToState(snapshot));
        _cool();
        vm.prank(MINER);
        game.mineFlip{gas: 2_000_000}();
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
        assertGt(host.orderLeft(PLAYER), 0, "gas shortage must preserve the unfinished atomic order");
        vm.etch(address(game), gameCode);
        assertEq(_mineAndReadOutcome(), full, "low-gas checkpoint changed player awards or their order");
    }

    function _mineAndReadOutcome() private returns (bytes32 digest) {
        _cool();
        vm.recordLogs();
        vm.prank(MINER);
        uint256 start = gasleft();
        game.mineFlip{gas: 25_000_000}();
        emit log_named_uint("cold complete mineFlip human gas (no transaction cap)", start - gasleft() + 21_064);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].emitter != address(game) || entries[i].topics[0] == MINER_WORK
                || entries[i].topics[0] == MINER_BOUNTY) continue;
            digest = keccak256(abi.encode(digest, entries[i].topics, entries[i].data));
        }
        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(PLAYER);
        digest = keccak256(abi.encode(digest, coinflip.coinflipAmount(PLAYER), sdgnrs.balanceOf(PLAYER),
            wwxrp.balanceOf(PLAYER), normal, high));
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        assertEq(host.orderLeft(PLAYER), 0, "engine admitted and completed the order");
        digest = keccak256(abi.encode(digest, host.outcome(PLAYER)));
    }

    function test_Cold100SaturatedCustomBoxes() public {
        _probe(BoxOrderLib.boCustoms(100, 10 ether), 0, false, 0xBEEF1234);
    }
    function test_Cold100MixedTierCoverAndPresale() public {
        _probe(BoxOrderLib.boOrder(24, 25, 25, 25, 10 ether), 10 ether, true, 0xBEEF1234);
    }
    function test_Cold101PresetBoxesIncludingCoverAndPresale() public {
        _probe(BoxOrderLib.boOrder(1, 1, 98, 0, 0), 10 ether, true, 0xBEEF1234);
    }
}
