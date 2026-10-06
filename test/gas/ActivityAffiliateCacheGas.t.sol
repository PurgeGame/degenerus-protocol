// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ActivityAffiliateCacheFixture} from "../fuzz/helpers/ActivityAffiliateCacheFixture.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @dev Production score helpers and real Affiliate history lookup. Isolate=true
/// resets transaction warmth, including on the second cache-hit transaction.
contract ActivityAffiliateCacheGasTest is ActivityAffiliateCacheFixture {
    function _measure(string memory label, bool cached) private {
        vm.cool(address(host));
        vm.cool(address(affiliate));
        vm.startStateDiffRecording();
        if (cached) host.scoreCached(PLAYER, 10, 25);
        else host.scoreUncached(PLAYER, 10, 25);
        uint256 used = vm.snapshotGasLastCall("affiliate-cache", label);
        (uint256 calls, uint256 stores) = _cacheAccesses(vm.stopAndReturnStateDiff(), address(host));
        emit log_named_string("scenario", label);
        emit log_named_uint("execution_gas", used);
        emit log_named_uint("affiliate_calls", calls);
        emit log_named_uint("mint_stores", stores);
    }

    function testGas_UncachedEmptyWord() public { host.seed(PLAYER, 0, 24); _measure("uncached_empty", false); }
    function testGas_CacheMissEmptyWord() public { host.seed(PLAYER, 0, 24); _measure("miss_empty", true); }
    function testGas_CacheMissCurseOnly() public { host.seed(PLAYER, uint256(2) << BitPackingLib.CURSE_COUNT_SHIFT, 24); _measure("miss_curse_only", true); }
    function testGas_UncachedExistingWord() public { host.seed(PLAYER, 1, 24); _measure("uncached_existing", false); }
    function testGas_CacheMissExistingWord() public { host.seed(PLAYER, 1, 24); _measure("miss_existing", true); }
    function testGas_CacheHitExistingWord() public {
        host.seed(PLAYER, 1, 24); host.scoreCached(PLAYER, 10, 25); _measure("hit_existing", true);
    }
    function testGas_UncachedHelperWithCacheHit() public {
        host.seed(PLAYER, 1, 24); host.scoreCached(PLAYER, 10, 25); _measure("uncached_helper_hit", false);
    }
}
