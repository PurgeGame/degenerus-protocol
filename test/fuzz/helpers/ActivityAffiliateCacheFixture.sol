// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {AffiliateStorage} from "../../helpers/AffiliateStorage.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameMintStreakUtils} from "../../../contracts/modules/DegenerusGameMintStreakUtils.sol";
import {DegenerusAffiliate} from "../../../contracts/DegenerusAffiliate.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

import {DegenerusQuests} from "../../../contracts/DegenerusQuests.sol";

contract ActivityAffiliateRealQA is DegenerusQuests, DegenerusAffiliate {
    constructor() DegenerusAffiliate(new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0)) {}
}

contract ActivityAffiliateStubQA is DegenerusAffiliate {
    constructor() DegenerusAffiliate(new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0)) {}
    function effectiveBaseStreakAndAfking(uint32) external pure returns (uint32, bool) { return (17, false); }
}

contract ActivityAffiliateCacheHost is DegenerusGameMintStreakUtils {
    function seed(address player, uint256 packed, uint24 currentLevel) external returns (uint32 id) {
        if (wallets.length == 0) wallets.push();
        if (player != address(0)) (id,) = _registerWallet(player, type(uint256).max);
        mintPacked_[id] = packed;
        level = currentLevel;
    }
    function packedOf(address player) external view returns (uint256) { return mintPacked_[_walletIdOf(player)]; }
    function score(address player, uint32 streak, uint24 basis) external view returns (uint256) {
        return _playerActivityScoreAt(_walletIdOf(player), streak, basis, level);
    }
    /// @dev Non-view transaction wrapper gives uncached/cached benchmarks identical
    /// CALL isolation and intrinsic-gas treatment; the score calculation is unchanged.
    function scoreUncached(address player, uint32 streak, uint24 basis) external returns (uint256) {
        return _playerActivityScoreAt(_walletIdOf(player), streak, basis, level);
    }
    function scoreCached(address player, uint32 streak, uint24 basis) external returns (uint256) {
        return _playerActivityScoreCachedAt(_walletIdOf(player), streak, basis, level);
    }
    function record(address player, uint24 target, uint32 units) external { _recordMintData(_walletIdOf(player), target, units); }
}

abstract contract ActivityAffiliateCacheFixture is Test {
    uint256 internal constant CACHE_MASK = ((uint256(1) << 30) - 1) << 173;
    address internal constant PLAYER = address(0xA11CE);
    uint32 internal constant PLAYER_ID = 1;
    ActivityAffiliateCacheHost internal host;
    DegenerusAffiliate internal affiliate;

    function setUp() public virtual {
        host = new ActivityAffiliateCacheHost();
        vm.etch(ContractAddresses.AFFILIATE, type(DegenerusAffiliate).runtimeCode);
        affiliate = DegenerusAffiliate(ContractAddresses.AFFILIATE);
    }

    function _seedEarnings(uint24 lvl, uint32 id, uint256 earned) internal {
        AffiliateStorage.set(address(affiliate), id, lvl, earned);
        // Exact views cover the two live levels; older bonus values are intentionally clipped.

    }

    function _stale(uint256 packed, uint24 lvl) internal pure returns (uint256) {
        return (packed & ~CACHE_MASK) | (uint256(lvl ^ 1) << 173);
    }

    function _cacheAccesses(Vm.AccountAccess[] memory accesses, address target)
        internal pure returns (uint256 affiliateCalls, uint256 stores)
    {
        for (uint256 i; i < accesses.length; ++i) {
            if (accesses[i].account == ContractAddresses.AFFILIATE && accesses[i].data.length >= 4 && bytes4(accesses[i].data) == DegenerusAffiliate.affiliateBonusPointsBest.selector) ++affiliateCalls;
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory access = accesses[i].storageAccesses[j];
                if (access.account == target && access.isWrite) ++stores;
            }
        }
    }
}
