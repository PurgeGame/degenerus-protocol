// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DeployProtocol} from "./DeployProtocol.sol";
import {DegenerusGameRngUtils} from "../../../contracts/modules/DegenerusGameRngUtils.sol";
import {RecyclingState} from "../../helpers/RecyclingState.sol";

/// @dev Exposes the production close/funding hook without requiring a whole VRF session.
contract RedemptionCloseHarness is DegenerusGameRngUtils {
    function close() external { _closeRedemptionBatch(); }
}
abstract contract RedemptionCloseTools is DeployProtocol {
    uint256 internal batchWord;
    function _openBatch() internal view returns (uint32 id) { (id,,,) = sdgnrs.redemptionBatchState(); }
    function _batchRoll(uint32 id) internal view returns (uint16 r) { (,,,,r,) = sdgnrs.redemptionBatches(id); }
    function _batchBase(address owner, uint32 id) internal view returns (uint256) {
        (uint128 total,,uint96 base,,,) = sdgnrs.redemptionBatches(id);
        (uint128 tokens,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(owner), id);
        return total == 0 ? 0 : uint256(base) * tokens / total;
    }
    function _closeFunded() internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        RedemptionCloseHarness(address(game)).close();
        vm.etch(address(game), code);
    }
    function _resolveTestBatch(uint32 id, uint16 roll) internal {
        if (_openBatch() == id) _closeFunded();
        batchWord = 2;
        while (21 + uint256(keccak256(abi.encode(uint256(84), batchWord))) % 155 != roll) ++batchWord;
        RecyclingState.seedWord(address(game), RecyclingState.readBuffer(address(game)), bytes32(batchWord));
        uint256 state = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32(state | (uint256(1) << 192)));
        (,, uint32 cursor,) = sdgnrs.redemptionBatchState();
        vm.prank(address(game));
        // Admits the 85k resolution bound with its 100k tail after a cold prelude; never a 600k claim.
        sdgnrs.runRedemptionWork(batchWord, 300_000);
        assertEq(_batchRoll(id), roll);
        (,, uint32 after_,) = sdgnrs.redemptionBatchState();
        assertEq(after_, cursor, "resolution only: no claim settled");
    }
}
