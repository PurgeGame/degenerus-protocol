// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract HeaderTailHarness is DegenerusGameStorage {
    mapping(uint24 => uint256[256]) internal legacy;
    function prepare(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function stamp(uint24 lvl) external view returns(uint24) { return _ticketBufferLevel(lvl); }
    function bits(uint24 lvl) external view returns(uint256) { return traitBucketLive[lvl & 1]; }
    function header(uint24 lvl, uint8 trait) external view returns(uint256) { return lvlTraitEntry[lvl & 1][trait]; }
    function rawWord(uint24 lvl,uint8 trait,uint256 i) external view returns(uint256 word) {
        uint256 elem=_traitBufferBase(lvl)+trait;
        assembly ("memory-safe") { mstore(0,elem) word:=sload(add(keccak256(0,32),i)) }
    }
    function lengths(uint24 lvl,uint8 trait) external view returns(uint256 a,uint256 b) {
        a=_bucketLengthUnchecked(lvl,trait);
        uint256 h=legacy[lvl & 1][trait];
        b=uint24(h>>232)==lvl ? (h<<24)>>24 : 0;
    }
    function words(uint24 lvl,uint8 trait,uint256 i) external view returns(uint256 a,uint256 b) {
        a=_bucketWordAtUnchecked(lvl,trait,i*8);
        uint256 elem=_legacyBase(lvl)+trait;
        assembly ("memory-safe") { mstore(0,elem) b:=sload(add(keccak256(0,32),i)) }
    }
    function run(uint24 lvl,uint8 trait,uint32 owner,uint256 n) external returns(uint256 f,uint256 d,uint256 rf,uint256 rd) {
        (f,d)=_bucketAppendRun(_traitBufferBase(lvl),trait,owner,n,lvl);
        (rf,rd)=_legacyRun(_legacyBase(lvl),trait,owner,n,lvl);
    }
    function lanes(uint24 lvl,uint8 trait,uint256 word,uint256 n) external returns(uint256 f,uint256 d,uint256 rf,uint256 rd) {
        (f,d)=_bucketAppendLanes(_traitBufferBase(lvl),trait,word,n,lvl);
        (rf,rd)=_legacyLanes(_legacyBase(lvl),trait,word,n,lvl);
    }
    function _legacyBase(uint24 lvl) private pure returns(uint256 base) {
        assembly ("memory-safe") { mstore(0,and(lvl,1)) mstore(32,legacy.slot) base:=keccak256(0,64) }
    }
    function _legacyRun(
        uint256 levelSlot,
        uint8 traitId,
        uint256 ownerIdx,
        uint256 occurrences,
        uint24 lvl
    ) internal returns (uint256 fresh, uint256 dirty) {
        assembly ("memory-safe") {
            let elem := add(levelSlot, traitId)
            let header := sload(elem)
            let len := 0
            if eq(shr(232, header), lvl) { len := shr(24, shl(24, header)) }
            sstore(elem, or(shl(232, lvl), add(len, occurrences)))
            switch len
            case 0 {
                fresh := 1
            }
            default {
                dirty := 1
            }
            mstore(0x00, elem)
            let w := add(keccak256(0x00, 0x20), shr(3, len))
            let lane := and(len, 7)
            // Replicate the owner index once; fill a partial tail in one masked write.
            let full := mul(ownerIdx, 0x0000000100000001000000010000000100000001000000010000000100000001)
            if lane {
                let take := sub(8, lane)
                if lt(occurrences, take) { take := occurrences }
                let prefix := and(full, sub(shl(shl(5, take), 1), 1))
                sstore(w, or(and(sload(w), sub(shl(shl(5, lane), 1), 1)), shl(shl(5, lane), prefix)))
                dirty := add(dirty, 1)
                occurrences := sub(occurrences, take)
                w := add(w, 1)
            }
            // Whole words: the lane replicated eight times.
            for {} gt(occurrences, 7) {} {
                sstore(w, full)
                fresh := add(fresh, 1)
                w := add(w, 1)
                occurrences := sub(occurrences, 8)
            }
            // Leading lanes of a fresh final word.
            if occurrences {
                sstore(w, and(full, sub(shl(shl(5, occurrences), 1), 1)))
                fresh := add(fresh, 1)
            }
        }
    }

    /// @dev Append `count` distinct lanes, already packed into `lanesWord` at positions
    ///      0..count-1 (every higher lane zero), to the bucket at `levelSlot + traitId`.
    ///      A partially filled tail word takes the leading lanes; the rest open a fresh
    ///      word. At most two stores for any count up to eight.
    function _legacyLanes(
        uint256 levelSlot,
        uint8 traitId,
        uint256 lanesWord,
        uint256 count,
        uint24 lvl
    ) internal returns (uint256 fresh, uint256 dirty) {
        assembly ("memory-safe") {
            let elem := add(levelSlot, traitId)
            let header := sload(elem)
            let len := 0
            if eq(shr(232, header), lvl) { len := shr(24, shl(24, header)) }
            sstore(elem, or(shl(232, lvl), add(len, count)))
            switch len
            case 0 {
                fresh := 1
            }
            default {
                dirty := 1
            }
            mstore(0x00, elem)
            let w := add(keccak256(0x00, 0x20), shr(3, len))
            let fill := and(len, 7)
            switch fill
            case 0 {
                sstore(w, lanesWord)
                fresh := add(fresh, 1)
            }
            default {
                // Lanes past the tail's free room shift out of the word and land in
                // the next one.
                sstore(w, or(and(sload(w), sub(shl(shl(5, fill), 1), 1)), shl(shl(5, fill), lanesWord)))
                dirty := add(dirty, 1)
                let room := sub(8, fill)
                if gt(count, room) {
                    sstore(add(w, 1), shr(shl(5, room), lanesWord))
                    fresh := add(fresh, 1)
                }
            }
        }
    }

}

contract HeaderTailTest is Test {
    HeaderTailHarness h;
    function setUp() public { h=new HeaderTailHarness(); h.prepare(1); }
    function _prices(uint24 lvl,uint8 trait,uint256 n) private view returns (uint256 f,uint256 d) {
        (uint256 oldLen,)=h.lengths(lvl,trait);
        uint256 bits=h.bits(lvl);
        bool init=bits&(uint256(1)<<trait)==0;
        uint256 stores=1+(init?1:0)+((oldLen&7)+n)/8;
        if(h.header(lvl,trait)==0) ++f;
        if(init && bits==0) ++f;
        uint256 start=oldLen/8;
        uint256 end=start+((oldLen&7)+n)/8;
        for(uint256 w=start;w<end;++w) if(h.rawWord(lvl,trait,w)==0) ++f;
        d=stores-f;
    }
    function _run(uint24 lvl,uint8 trait,uint32 owner,uint256 n) private {
        (uint256 ef,uint256 ed)=_prices(lvl,trait,n);
        (uint256 f,uint256 d,,)=h.run(lvl,trait,owner,n);
        assertEq(f,ef,"zero-valued slots"); assertEq(d,ed,"nonzero-valued slots"); _check(lvl,trait);
    }
    function _lanes(uint24 lvl,uint8 trait,uint256 word,uint256 n) private {
        (uint256 ef,uint256 ed)=_prices(lvl,trait,n);
        (uint256 f,uint256 d,,)=h.lanes(lvl,trait,word,n);
        assertEq(f,ef,"zero-valued slots"); assertEq(d,ed,"nonzero-valued slots"); _check(lvl,trait);
    }
    function _check(uint24 lvl,uint8 trait) private {
        (uint256 n,uint256 rn)=h.lengths(lvl,trait); assertEq(n,rn,"length");
        for(uint256 i; i<(n+7)/8; ++i) {
            (uint256 word,uint256 ref)=h.words(lvl,trait,i); assertEq(word,ref,"ordered logical word");
        }
        uint256 head=h.header(lvl,trait);
        uint256 k=n&7; uint256 mask=k==0 ? 0 : (uint256(1)<<(k*32))-1;
        assertEq((head>>32)&~mask,0,"unused header lanes zero");
    }
    function testFuzz_MixedRunAndLaneEquivalence(uint256 seed) public {
        for(uint256 i; i<48; ++i) {
            seed=uint256(keccak256(abi.encode(seed,i)));
            uint8 trait=uint8(seed)&3;
            if(seed&4==0) _run(1,trait,uint32(seed>>8),uint8(seed>>40)%32);
            else {
                uint256 n=1+(uint8(seed>>40)%8);
                uint256 mask=n==8 ? type(uint256).max : (uint256(1)<<(n*32))-1;
                _lanes(1,trait,seed&mask,n);
            }
        }
    }
    function test_EveryTailAndCountBoundary() public {
        for(uint8 tail;tail<8;++tail) for(uint256 n;n<18;++n) {
            uint24 lvl=uint24(1+2*(uint256(tail)*18+n)); h.prepare(lvl);
            _run(lvl,255,0,tail); _run(lvl,255,type(uint32).max,n); _run(lvl,255,0xabcdef01,9);
        }
    }
    function test_DataWordsOnlyWrittenOnCompletion() public {
        _run(1,7,23,7); assertEq(h.rawWord(1,7,0),0,"tail is only in header");
        uint256 tail=h.header(1,7)>>32;
        _run(1,7,99,1); assertEq(h.rawWord(1,7,0),tail|(uint256(99)<<224));
        assertEq(h.header(1,7),8,"completed tail cleared");
        _run(1,7,42,3); assertEq(h.rawWord(1,7,1),0,"next tail also only in header");
    }
    function test_AbsentTraitCannotReappearAfter256Takeovers() public {
        _run(1,7,23,7); uint256 stale=h.header(1,7);
        for(uint24 lvl=3;lvl<=515;lvl+=2) h.prepare(lvl);
        assertEq(h.header(515,7),stale,"takeover never clears 256 headers");
        assertEq(h.bits(515),0,"validity cleared despite stale payload");
        (uint256 n,)=h.lengths(515,7); assertEq(n,0);
        _run(515,7,0,1); assertEq(h.header(515,7),1,"zero owner overwrites stale lanes");
    }
    function test_SameLevelAndOtherParityPreserveBits() public {
        _run(1,0,11,1); _run(1,255,12,1);
        uint256 bits=h.bits(1); h.prepare(1); assertEq(h.bits(1),bits);
        h.prepare(2); _run(2,15,33,7); assertEq(h.bits(1),bits);
        h.prepare(3); assertEq(h.bits(3),0); assertEq(h.bits(2),uint256(1)<<15);
        (uint256 n,)=h.lengths(2,15); assertEq(n,7);
    }
    function test_UnpreparedFutureIsEmptyEvenWhenBitmapSet() public {
        _run(1,7,23,7); (uint256 n,)=h.lengths(3,7); assertEq(n,0);
    }
}
