// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {SdgnrsWhaleBuyStageGas} from "../gas/SdgnrsWhaleBuyStageGas.t.sol";

/// @notice Compare the real automatic whale checkpoint against the committed P1 runtimes.
/// @dev Uses the same fixture and cold measurement as the inherited candidate test.
contract ConsolidationAutoWhaleGas is SdgnrsWhaleBuyStageGas {
    function test_BaselineWhalePurchaseIncrement_FitsChargedWeight() public {
        _baseline(address(game), "DegenerusGame");
        _baseline(address(mintModule), "DegenerusGameMintModule");
        _baseline(address(whaleModule), "DegenerusGameWhaleModule");
        _baseline(address(degenesisModule), "DegenerusGameDegenesisModule");
        test_WhalePurchaseIncrement_FitsChargedWeight();
    }

    function _baseline(address target, string memory name) private {
        string memory directory = vm.envOr("DIFFERENTIAL_BASELINE_DIR", string(".planning/consolidation/baseline/fixture-artifacts"));
        bytes memory code = vm.parseJsonBytes(vm.readFile(string.concat(directory, "/", name, ".sol/", name, ".json")), ".deployedBytecode.object");
        require(code.length != 0, "missing baseline runtime");
        vm.etch(target, code);
    }
}
