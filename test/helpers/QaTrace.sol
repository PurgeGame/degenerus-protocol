// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Vm, VmSafe} from "forge-std/Vm.sol";

/// @dev Observe the storage effects of internalized QA calls, including their order.
///      Independent mapping preimages and the published seven-lane codec are used.
library QaTrace {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant QUESTS = 0x04343aaa474371a66bb47cad27e6432f6ed56b02c7b23c6e11e4d1818f7af200;
    uint256 internal constant AFFILIATE = 0x93b2738aa52d403a1d6cd7cad14e72a7cda308b6a92d312ff0746cbfb7eec800;

    function questKey(address host, bytes32 slot) internal view returns (bool found, uint32 id) {
        bytes32 key; bytes32 parent;
        (found,key,parent) = vm.getMappingKeyAndParentOf(host,slot);
        found = found && (uint256(parent) == QUESTS + 1 || uint256(parent) == QUESTS + 2);
        id = uint32(uint256(key));
    }

    function stakeKey(address host, Vm.StorageAccess memory s) private view returns (bool found, uint32 id, uint24 page) {
        uint256 tag = uint24(uint256(s.newValue) >> 224);
        if (tag == 0) return (false,0,0);
        page = uint24(tag - 1);
        bytes32 key; bytes32 parent;
        if (uint256(s.slot) >= page % 15) (found,key,parent) = vm.getMappingKeyAndParentOf(host,bytes32(uint256(s.slot) - page % 15));
        if (found && parent == bytes32(0)) return (true,uint32(uint256(key)),page);
        (found,key,parent) = vm.getMappingKeyAndParentOf(host,s.slot);
        if (!found || uint256(key) != page) return (false,0,page);
        (found,key,parent) = vm.getMappingKeyAndParentOf(host,parent);
        return (found && uint256(parent) == 9,uint32(uint256(key)),page);
    }

    struct Credits { bytes[] values; uint256 count; }

    function credits(Vm.AccountAccess[] memory acc, address host) internal view returns (bytes[] memory result) {
        return _credits(acc,host,false);
    }

    function affiliateCredits(Vm.AccountAccess[] memory acc,address host) internal view returns(bytes[] memory) {
        return _credits(acc,host,true);
    }

    function _credits(Vm.AccountAccess[] memory acc,address host,bool affiliateOnly) private view returns(bytes[] memory result) {
        uint256 cap;
        for (uint256 i; i < acc.length; ++i) cap += acc[i].storageAccesses.length * 7;
        Credits memory sink = Credits(new bytes[](cap),0);
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].reverted) continue;
            if (affiliateOnly && acc[i].kind == VmSafe.AccountAccessKind.Call && acc[i].account == host) {
                // Game's subscriber settlement can credit the same host during a claim.
                // These credit wrappers have no external callbacks: all their writes are
                // in this Call record. Resume records can group later parent writes, so
                // attribute those by StorageAccess.account rather than AccountAccess.account.
                bytes4 sel=bytes4(acc[i].data);
                if (sel==bytes4(keccak256("creditFlip(uint32,uint256)")) || sel==bytes4(keccak256("creditFlipPair(uint32,uint256,uint32,uint256)")) || sel==bytes4(keccak256("creditFlipBatch(uint32[],uint256[])"))) continue;
            }
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) _recordCredit(acc[i].storageAccesses[j],host,sink);
        }
        result=sink.values;uint256 n=sink.count;
        assembly ("memory-safe") { mstore(result,n) }
    }

    function _recordCredit(Vm.StorageAccess memory s,address host,Credits memory sink) private view {
        if (s.reverted || !s.isWrite || s.account != host) return;
        (bool found,uint32 id,uint24 page) = stakeKey(host,s);
        if (!found) return;
        uint256 previous = uint24(uint256(s.previousValue) >> 224) == page + 1 ? uint256(s.previousValue) : 0;
        for (uint256 lane; lane < 7; ++lane) {
            uint256 before = uint32(previous >> (lane * 32));
            uint256 after_ = uint32(uint256(s.newValue) >> (lane * 32));
            if (after_ > before) sink.values[sink.count++] = abi.encode(id,after_ - before);
        }
    }

    function questId(Vm.AccountAccess[] memory acc,address host) internal view returns (uint32 id) {
        bool seen;
        for (uint256 i; i < acc.length; ++i) for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
            Vm.StorageAccess memory s=acc[i].storageAccesses[j];
            if (acc[i].reverted || s.reverted || s.account != host) continue;
            (bool found,uint32 key)=questKey(host,s.slot);
            if (!found) continue;
            require(!seen || id==key,"multiple quest wallets"); id=key;seen=true;
        }
        require(seen,"no quest effect");
    }

    function order(Vm.AccountAccess[] memory acc,address host,uint32 id) internal view returns (uint256 quest,uint256 credit) {
        quest=type(uint256).max;credit=type(uint256).max;uint256 at;
        for (uint256 i; i < acc.length; ++i) for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
            ++at;Vm.StorageAccess memory s=acc[i].storageAccesses[j];
            if (acc[i].reverted || s.reverted || s.account!=host) continue;
            (bool found,uint32 key)=questKey(host,s.slot);
            if(found && key==id && quest==type(uint256).max)quest=at;
            (found,key,)=stakeKey(host,s);
            if(found && s.isWrite && key==id && credit==type(uint256).max)credit=at;
        }
    }
}
