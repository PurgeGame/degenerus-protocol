// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
contract StableOwnersHarness is DegenerusGameStorage {
    constructor() { level = 3; }
    function credit(address p, uint24 lvl, uint32 n) external { _queueEntries(p, lvl, n, false); }
    function creditScaled(address p, uint24 lvl, uint32 n) external { _queueEntriesScaled(p, lvl, n, false); }
    function flip() external { ticketWriteSlot = !ticketWriteSlot; }
    function owed(uint24 key, address p) external view returns (uint80) { return _entriesOwed(key,p); }
    function keys(uint24 lvl) external view returns(uint24,uint24,uint24) { return(_tqReadKey(lvl),_tqWriteKey(lvl),_tqFarFutureKey(lvl)); }
    function consume(uint24 key, address p) external { _setEntryOwed(key,ticketOwnerId[p],0); _releaseTicketQueue(key); }
    function release(uint24 key) external { _releaseTicketQueue(key); }
    function physical(uint24 key) external pure returns(uint24) { return _ticketQueueStorageKey(key); }
    function total(uint24 lvl,address p) external view returns(uint32) { return _entriesOwedTotal(lvl,p); }
    function extsload(bytes32 slot) external view returns(bytes32 value) { assembly ("memory-safe") { value := sload(slot) } }
    function id(address p) external view returns(uint32) { return ticketOwnerId[p]; }
    function count() external view returns(uint256) { return ticketOwners.length; }
    function word(uint24 lvl, address p) external view returns(uint256) { return ticketPending[_ticketPendingStorageKey(lvl)][ticketOwnerId[p]]; }
    function len(uint24 key) external view returns(uint256) { return _ticketQueueLength(key); }
    function setLevel(uint24 n) external { level = n; }
    function fill(uint256 n) external { assembly ("memory-safe") { sstore(ticketOwners.slot,n) } }
    function bucket(uint24 lvl, address p) external { _setTicketBufferLevel(lvl); uint256 idx=uint256(_registerEntryOwner(p,lvl)>>OWNER_IDX_SHIFT)-1; _bucketAppendRun(_traitBufferBase(lvl),0,idx,8,lvl); }
    function bucketOwner(uint24 lvl,uint256 i) external view returns(address) { return _bucketOwnerAtUnchecked(lvl,0,i); }
}
contract StableEntryOwnersTest is Test {
    StableOwnersHarness h;
    address constant A=address(0xA11CE);
    address constant B=address(0xB0B);
    function setUp() public { h=new StableOwnersHarness(); }
    function test_IdSurvivesDrainAndRequeue() public {
        (,uint24 wk,)=h.keys(3);h.credit(A,3,4);uint32 id=h.id(A);
        h.consume(wk,A);assertEq(h.owed(wk,A),0);assertEq(h.word(3,A),uint256(1)<<255);
        h.credit(A,3,8);assertEq(h.id(A),id);assertEq(h.count(),1);assertEq(h.len(wk),1);assertEq(uint32(h.owed(wk,A)>>8),8);
    }
    function test_ReadAndWriteCreditAreIndependent() public {
        h.credit(A,3,4);h.flip();(uint24 rk,uint24 wk,)=h.keys(3);
        h.credit(A,3,8);assertEq(h.count(),1);assertEq(uint32(h.owed(rk,A)>>8),4);assertEq(uint32(h.owed(wk,A)>>8),8);
        h.consume(rk,A);assertEq(h.owed(rk,A),0);assertEq(uint32(h.owed(wk,A)>>8),8);
    }
    function test_FutureAndNormalCreditAreIndependent() public {
        h.credit(A,5,4);(,,uint24 ff)=h.keys(5);h.setLevel(4);h.credit(A,5,12);(,uint24 wk,)=h.keys(5);
        assertEq(uint32(h.owed(ff,A)>>8),4);assertEq(uint32(h.owed(wk,A)>>8),12);assertEq(h.count(),1);
        h.consume(ff,A);assertEq(uint32(h.owed(wk,A)>>8),12);
    }
    function test_FractionalCreditQueuesOnlyOnce() public {
        (,uint24 wk,)=h.keys(3);h.creditScaled(A,3,1);h.creditScaled(A,3,2);
        assertEq(h.len(wk),1);assertEq(uint8(h.owed(wk,A)),3);assertEq(h.count(),1);
    }
    function test_ZeroCreditDoesNotAllocate() public { h.credit(A,3,0);h.creditScaled(A,3,0);assertEq(h.count(),0);assertEq(h.id(A),0); }
    function test_BucketOwnerSurvivesOtherLevelsAndPendingClears() public {
        h.credit(A,3,4);h.bucket(3,A);h.credit(B,4,4);h.bucket(4,B);
        (,uint24 wk,)=h.keys(3);h.consume(wk,A);h.credit(B,5,4);
        for(uint256 i;i<8;++i)assertEq(h.bucketOwner(3,i),A);
        assertEq(h.count(),2);
    }
    function test_CeilingDoesNotPreventExistingOwnerCredits() public {
        h.credit(A,3,4);(,uint24 wk,)=h.keys(3);h.consume(wk,A);h.fill(type(uint32).max);
        h.credit(A,4,4);assertEq(h.id(A),1);vm.expectRevert(bytes4(keccak256("E()")));h.credit(B,4,4);
    }
    function test_LastNonzeroIdIsUsable() public { h.fill(uint256(type(uint32).max)-1);h.credit(A,3,4);assertEq(h.id(A),type(uint32).max);assertEq(h.count(),type(uint32).max); }
    function test_QueueRootsRecycleAcrossThreeCenturiesKeepingOneId() public {
        for(uint24 lvl=1;lvl<=385;++lvl) {
            h.setLevel(lvl-1);h.credit(A,lvl,4);(,uint24 wk,)=h.keys(lvl);
            assertEq(h.id(A),1);assertEq(h.count(),1);assertEq(h.len(wk),1);
            assertEq(h.physical(wk),uint24((lvl-1)%100+1));
            h.consume(wk,A);assertEq(h.len(wk),0);
        }
    }
    function test_StaleReleaseCannotClearNewOccupant() public {
        h.setLevel(0);h.credit(A,1,4);(,uint24 oldKey,)=h.keys(1);h.consume(oldKey,A);
        h.setLevel(100);h.credit(A,101,8);(,uint24 newKey,)=h.keys(101);
        h.release(oldKey);assertEq(h.len(oldKey),0);assertEq(h.len(newKey),1);
        assertEq(uint32(h.owed(newKey,A)>>8),8);
    }
    function test_LiveQueueCollisionRevertsWithoutLosingCreditsOrAllocatingId() public {
        h.setLevel(0);h.credit(A,1,4);(,uint24 oldKey,)=h.keys(1);
        h.setLevel(100);vm.expectRevert(bytes4(keccak256("E()")));h.credit(B,101,8);
        assertEq(h.len(oldKey),1);assertEq(uint32(h.owed(oldKey,A)>>8),4);
        assertEq(h.id(B),0);assertEq(h.count(),1);
    }
    function test_PendingWordReusesSameRootAndAuthenticatesLaterLevel() public {
        h.setLevel(0);h.credit(A,1,4);(,uint24 oldKey,)=h.keys(1);h.consume(oldKey,A);
        assertEq(h.word(1,A),uint256(1)<<255);
        h.setLevel(128);h.credit(A,129,8);(,uint24 newKey,)=h.keys(129);
        assertEq(h.word(1,A),h.word(129,A));assertEq(h.owed(oldKey,A),0);
        assertEq(h.total(1,A),0);assertEq(h.total(129,A),8);
        assertEq(uint32(h.owed(newKey,A)>>8),8);
        assertEq((h.word(129,A)>>126)&0xffffff,129);
        h.consume(newKey,A);assertEq(h.word(1,A),uint256(1)<<255);
    }
    function test_CurrentAndCenturyAheadFutureKeepSeparateQueueDomains() public {
        h.setLevel(0);h.credit(A,1,4);h.credit(A,101,8);
        (,uint24 wk,)=h.keys(1);(,,uint24 ff)=h.keys(101);
        assertEq(h.len(wk),1);assertEq(h.len(ff),1);assertEq(h.count(),1);
        h.consume(wk,A);assertEq(uint32(h.owed(ff,A)>>8),8);assertEq(h.len(ff),1);
    }
    function test_LensPermanentIdentityReadsGlobalRoots() public {
        DegenerusGameLens lens=new DegenerusGameLens();
        assertEq(lens.walletIdOf(address(h),A),0);assertEq(lens.walletOfId(address(h),0),address(0));
        h.credit(A,3,4);uint32 id=h.id(A);
        assertEq(lens.walletIdOf(address(h),A),id);assertEq(lens.walletOfId(address(h),id),A);
        assertEq(lens.walletOfId(address(h),id+1),address(0));
        (,uint24 wk,)=h.keys(3);h.consume(wk,A);
        h.setLevel(130);h.credit(A,131,4);assertEq(lens.walletIdOf(address(h),A),id);assertEq(lens.walletOfId(address(h),id),A);
    }
    function testFuzz_AllLanesPreserved(uint32 readAmount,uint32 writeAmount,uint32 futureAmount) public {
        readAmount=uint32(bound(readAmount,1,1e9));writeAmount=uint32(bound(writeAmount,1,1e9));futureAmount=uint32(bound(futureAmount,1,1e9));
        h.credit(A,5,futureAmount);h.setLevel(4);h.credit(A,5,readAmount);h.flip();h.credit(A,5,writeAmount);
        (uint24 rk,uint24 wk,uint24 ff)=h.keys(5);h.consume(rk,A);
        assertEq(uint32(h.owed(wk,A)>>8),writeAmount);assertEq(uint32(h.owed(ff,A)>>8),futureAmount);
    }
}
