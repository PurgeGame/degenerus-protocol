// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameMintStreakUtils} from "../../../contracts/modules/DegenerusGameMintStreakUtils.sol";
import {DegenerusAffiliate} from "../../../contracts/DegenerusAffiliate.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

contract ActivityAffiliateCacheHost is DegenerusGameMintStreakUtils {
    function seed(address player, uint256 packed, uint24 currentLevel) external {
        mintPacked_[player] = packed;
        level = currentLevel;
    }
    function packedOf(address player) external view returns (uint256) { return mintPacked_[player]; }
    function score(address player, uint32 streak, uint24 basis) external view returns (uint256) {
        return _playerActivityScoreAt(player, streak, basis, level);
    }
    /// @dev Non-view transaction wrapper gives uncached/cached benchmarks identical
    /// CALL isolation and intrinsic-gas treatment; the score calculation is unchanged.
    function scoreUncached(address player, uint32 streak, uint24 basis) external returns (uint256) {
        return _playerActivityScoreAt(player, streak, basis, level);
    }
    function scoreCached(address player, uint32 streak, uint24 basis) external returns (uint256) {
        return _playerActivityScoreCachedAt(player, streak, basis, level);
    }
    function record(address player, uint24 target, uint32 units) external { _recordMintData(player, target, units); }
}

abstract contract ActivityAffiliateCacheFixture is Test {
    uint256 internal constant CACHE_MASK = ((uint256(1) << 30) - 1) << 185;
    address internal constant PLAYER = address(0xA11CE);
    ActivityAffiliateCacheHost internal host;
    DegenerusAffiliate internal affiliate;

    function setUp() public virtual {
        host = new ActivityAffiliateCacheHost();
        vm.etch(ContractAddresses.AFFILIATE, type(DegenerusAffiliate).runtimeCode);
        affiliate = DegenerusAffiliate(ContractAddresses.AFFILIATE);
    }

    function _seedEarnings(uint24 lvl, address player, uint256 earned) internal {
        // Root1 is the private affiliateCoinEarned mapping; verify its public view
        // immediately so storage-layout drift cannot silently weaken this fixture.
        bytes32 root = keccak256(abi.encode(lvl, uint256(1)));
        vm.store(address(affiliate), keccak256(abi.encode(player, root)), bytes32(earned));
        assertEq(affiliate.affiliateScore(lvl, player), earned);
    }

    function _stale(uint256 packed, uint24 lvl) internal pure returns (uint256) {
        return (packed & ~CACHE_MASK) | (uint256(lvl ^ 1) << 185);
    }

    function _cacheAccesses(Vm.AccountAccess[] memory accesses, address target)
        internal pure returns (uint256 affiliateCalls, uint256 stores)
    {
        for (uint256 i; i < accesses.length; ++i) {
            if (accesses[i].account == ContractAddresses.AFFILIATE) ++affiliateCalls;
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory access = accesses[i].storageAccesses[j];
                if (access.account == target && access.isWrite) ++stores;
            }
        }
    }
}
