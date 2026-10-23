// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {HumanOrderRepricer} from "./HumanOrderNativeGas.t.sol";

/// @dev Seeds compact entries straight into the sealed read buffer (three 85-bit lanes per word)
///      with a chosen 12-bit score code, and runs the production opener and worker over them.
contract CompactOrderGasSeed is DegenerusGame {
    /// @dev `codes.length` entries of `input` for `player`, entry i in word i / 3, lane i % 3,
    ///      each with score code codes[i]; the read buffer holds exactly those entries.
    function seedOrders(address player, uint256 input, uint256[] calldata codes, uint256 entropy) external {
        _registerWallet(player, type(uint256).max);
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
        (uint256 fields,) = _decodeBoxOrder(input, 100);
        uint256[] storage q = boxQueue[idx];
        uint256 base;
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            base := keccak256(0x00, 0x20)
        }
        for (uint256 i; i < codes.length; ++i) {
            uint256 entry = fields | uint256(_walletIdOf(player)) | (codes[i] << LB_SCORE_SHIFT);
            uint256 slot = base + i / 3;
            uint256 shift = (i % 3) * LB_ENTRY_BITS;
            assembly ("memory-safe") {
                switch shift
                case 0 { sstore(slot, entry) }
                default { sstore(slot, or(sload(slot), shl(shift, entry))) }
            }
        }
        boxReadCount = uint32(codes.length);
        boxCursor = 0;
        _setCurrentPrizePool(10_000 ether);
        _setPrizePools(10_000 ether, 10_000 ether);
    }

    /// @dev The worker's per-entry step for entry `position`.
    function rawAtomic(uint256 position) external returns (uint256 boxes) {
        uint48 idx = _rngReadBuffer();
        uint256 entry = _boxEntryAt(idx, position);
        boxes = _boxEntryCount(entry);
        boxCursor = uint32(position + 1);
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature("resolveHumanBoxOrder(uint48,uint256,uint256,uint256,uint24)",
                idx, position, entry, _lootboxWord(idx), level + 1)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    function work(uint256 allowance) external returns (bool progressed, bool done) {
        (bool ok, bytes memory returned) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runHumanBoxWork_g315(uint256)", allowance));
        if (!ok) assembly ("memory-safe") { revert(add(returned, 32), mload(returned)) }
        (progressed, done,) = abi.decode(returned, (bool, bool, uint256));
    }

    function entryAt(uint256 position) external view returns (uint256) {
        return _boxEntryAt(_rngReadBuffer(), position);
    }

    function cursor() external view returns (uint256) {
        return boxCursor;
    }
}

/// @title LootboxCompactOrderLivenessGas -- compact order opens at the input extremes
/// @notice The 2,000 ETH per-box cap at 100 boxes, with the 12-bit score code at its extremes
///         (0, the last exact code 2,042, and 4,039, the activity cap's code), opened cold over
///         many words by the production opener against the entry bound HUMAN_ENTRY_GAS + 100 x
///         HUMAN_BOX_GAS on Osaka and on the no-reservoir Glamsterdam total (whose rare 100-box
///         excess over 10M is the accepted exception). Three such entries packed in one queue
///         word (lanes 0, 1, 2, mixed codes) then run through the production human-box worker at
///         an allowance that admits exactly one entry: each call must resolve exactly that entry
///         with no overspend (WorkGasBound) and the queue must finish in three calls.
contract LootboxCompactOrderLivenessGas is DeployProtocol {
    address private constant PLAYER = address(0xC0AA01);
    uint256 private constant MAX_BOX = 2_000 ether;

    CompactOrderGasSeed private host;
    HumanOrderRepricer private repricer;

    function setUp() public {
        _deployProtocol(false);
        vm.deal(address(game), 500_000 ether);
        vm.etch(address(game), type(CompactOrderGasSeed).runtimeCode);
        host = CompactOrderGasSeed(payable(address(game)));
        repricer = new HumanOrderRepricer();
    }

    function _cool() private {
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(address(sdgnrs)); vm.cool(address(wwxrp)); vm.cool(address(crapsBattle));
        vm.cool(ContractAddresses.GAME_MINER_MODULE); vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE); vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE); vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
    }

    function _codes1(uint256 code) private pure returns (uint256[] memory c) {
        c = new uint256[](1);
        c[0] = code;
    }

    function test_Max2000EthBoxesAtScoreCodeExtremes() public {
        uint256[3] memory codes = [uint256(0), 2042, 4039];
        uint256 bound = GasBounds.HUMAN_ENTRY_GAS + 100 * GasBounds.HUMAN_BOX_GAS;
        uint256 peakOsaka;
        uint256 peakTotal;
        for (uint256 k; k < codes.length; ++k) {
            uint256 codePeak;
            for (uint256 w; w < 8; ++w) {
                uint256 base = vm.snapshotState();
                host.seedOrders(PLAYER, BoxOrderLib.boCustoms(100, MAX_BOX), _codes1(codes[k]),
                    uint256(keccak256(abi.encode("compact-extreme", k, w))));
                assertEq(BoxOrderLib.boScoreCode(host.entryAt(0)), codes[k], "seeded code");
                assertEq(BoxOrderLib.boSizeWei(host.entryAt(0)), MAX_BOX, "2,000 ETH per box");
                uint256 snap = vm.snapshotState();
                _cool();
                uint256 beforeGas = gasleft();
                uint256 boxes = host.rawAtomic{gas: 25_000_000}(0);
                uint256 osaka = beforeGas - gasleft();
                assertEq(boxes, 100, "100 boxes");
                vm.revertToStateAndDelete(snap);
                _cool();
                vm.startStateDiffRecording();
                host.rawAtomic{gas: 25_000_000}(0);
                VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
                GlamsterdamReprice.Result memory r = repricer.quote(osaka, acc, address(game));
                uint256 total = r.glamsterdamExec + r.stateGas;
                if (osaka > peakOsaka) peakOsaka = osaka;
                if (total > peakTotal) peakTotal = total;
                if (osaka > codePeak) codePeak = osaka;
                assertLe(osaka, bound, "Osaka entry within its bound");
                assertLe(total, bound, "no-reservoir Glamsterdam entry within its bound");
                vm.revertToStateAndDelete(base);
            }
            emit log_named_uint(string.concat("score code ", vm.toString(codes[k]), ": peak cold osaka"), codePeak);
        }
        emit log_named_uint("100 x 2,000 ETH entry: peak cold osaka", peakOsaka);
        emit log_named_uint("100 x 2,000 ETH entry: peak no-reservoir glamsterdam", peakTotal);
        emit log_named_uint("entry bound HUMAN_ENTRY_GAS + 100 x HUMAN_BOX_GAS", bound);
    }

    /// forge-config: default.fuzz.runs = 12
    function testFuzz_ThreeOrdersOneSlotOnePerCall(uint256 seed) public {
        uint256[] memory codes = new uint256[](3);
        codes[0] = 0;
        codes[1] = 2042 + seed % 1998;
        codes[2] = 4039;
        uint256 perBox = seed >> 16 & 1 == 0 ? MAX_BOX : (10 + (seed >> 32) % 1_999_990) * 0.001 ether;
        host.seedOrders(PLAYER, BoxOrderLib.boCustoms(100, perBox), codes, uint256(keccak256(abi.encode(seed))));
        for (uint256 i; i < 3; ++i) assertEq(BoxOrderLib.boScoreCode(host.entryAt(i)), codes[i], "lane code");
        uint256 allowance = GasBounds.HUMAN_ENTRY_GAS + 100 * GasBounds.HUMAN_BOX_GAS + GasBounds.HUMAN_TAIL_GAS
            + MineFlipGas.CHECK_RESERVE + 100_000;
        for (uint256 i; i < 3; ++i) {
            _cool();
            (bool progressed, bool done) = host.work{gas: allowance + 3_000_000}(allowance);
            assertTrue(progressed, "the admitted entry resolved");
            assertEq(host.cursor(), i + 1, "exactly one entry per call");
            assertEq(done, i == 2, "the queue finishes with the third entry");
        }
    }
}
