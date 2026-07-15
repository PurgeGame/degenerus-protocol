// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title DecimatorOffsetIsolation -- terminal vs. regular winning-offset slot isolation
/// @notice Storage-level regression for the terminal-decimator offset relocation.
///
/// Context: the REGULAR decimator (`runDecimatorJackpot`) snapshots its winning subbuckets into
/// `decBucketOffsetPacked[lvl]`. The persistent regular round (`decClaimRounds[lvl]`, no expiry) is
/// keyed on the same level. Because the storage `level` lags the active purchase level by one, a
/// gameover can fire at level X while a level-X REGULAR round still holds unclaimed entries.
///
/// The terminal resolution (`runTerminalDecimatorJackpot`) now stores its packed winning subbuckets at
/// `decBucketOffsetPacked[lvl + 1]` rather than `decBucketOffsetPacked[lvl]`. This test proves that a
/// terminal resolution at level X leaves a pre-existing regular round's offset slot `[X]` untouched and
/// lands the terminal offsets at `[X + 1]` instead — the isolation that prevents a terminal write from
/// corrupting the regular round's winning-subbucket selector (which would otherwise mis-attribute
/// claimable beyond the reserved pool and/or revert honest regular claims).
contract DecimatorOffsetIsolationTest is DeployProtocol {
    // Authoritative slots from `forge inspect DegenerusGame storageLayout`:
    //   decBucketOffsetPacked      mapping(uint24  => uint64)   slot 44
    //   terminalDecBucketBurnTotal mapping(bytes32 => uint256)  slot 49
    //   lastTerminalDecClaimRound  struct (lvl in low bytes)    slot 50 (fresh game => 0)
    uint256 internal constant SLOT_DEC_OFFSET_PACKED = 43;
    uint256 internal constant SLOT_TERMINAL_BUCKET_BURN = 48;

    // Mirror of the module's denominator span (2..12 inclusive).
    uint8 internal constant DECIMATOR_MAX_DENOM = 12;

    // A live regular round's winning-subbucket selector, standing in for an unclaimed round at level X.
    uint64 internal constant SENTINEL = uint64(0xDEAD_BEEF_CAFE_F00D);

    function setUp() public {
        _deployProtocol();
    }

    /// @dev Storage key for decBucketOffsetPacked[lvl].
    function _offsetSlot(uint24 lvl) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(lvl), SLOT_DEC_OFFSET_PACKED));
    }

    /// @dev Storage key for terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, denom, sub))].
    function _terminalBurnSlot(
        uint24 lvl,
        uint8 denom,
        uint8 sub
    ) internal pure returns (bytes32) {
        bytes32 bucketKey = keccak256(abi.encode(lvl, denom, sub));
        return keccak256(abi.encode(bucketKey, SLOT_TERMINAL_BUCKET_BURN));
    }

    function test_terminalDecimator_doesNotCorruptRegularOffsetSlot() public {
        uint24 X = 100; // X != 0 keeps lastTerminalDecClaimRound.lvl (==0 on a fresh game) distinct.
        uint256 poolWei = 5 ether;
        uint256 rngWord = uint256(keccak256("decimator-offset-isolation-rng"));

        // 1) Stand in for a live, unclaimed REGULAR round: plant a sentinel selector at [X].
        vm.store(address(game), _offsetSlot(X), bytes32(uint256(SENTINEL)));
        assertEq(
            uint64(uint256(vm.load(address(game), _offsetSlot(X)))),
            SENTINEL,
            "sentinel not planted at decBucketOffsetPacked[X]"
        );
        // [X + 1] starts empty — proves the terminal write below is what populates it.
        assertEq(
            uint256(vm.load(address(game), _offsetSlot(X + 1))),
            0,
            "decBucketOffsetPacked[X + 1] should be empty pre-resolution"
        );

        // 2) Seed every (denom, sub) burn total so whichever subbucket the RNG selects has winners,
        //    forcing the terminal path past its `totalWinnerBurn == 0` early return into the offset write.
        for (uint8 denom = 2; denom <= DECIMATOR_MAX_DENOM; ++denom) {
            for (uint8 sub = 0; sub < denom; ++sub) {
                vm.store(
                    address(game),
                    _terminalBurnSlot(X, denom, sub),
                    bytes32(uint256(1 ether))
                );
            }
        }

        // 3) Drive the terminal resolution at level X through the game's self-call passthrough.
        //    address(game) == ContractAddresses.GAME (asserted by DeployCanary), so the self-call guard
        //    (msg.sender == address(this)) and the module's GAME guard (preserved through delegatecall)
        //    are both satisfied.
        vm.prank(address(game));
        (bool ok, bytes memory data) = address(game).call(
            abi.encodeWithSignature(
                "runTerminalDecimatorJackpot(uint256,uint24,uint256)",
                poolWei,
                X,
                rngWord
            )
        );
        assertTrue(ok, "runTerminalDecimatorJackpot reverted");
        uint256 returnAmountWei = abi.decode(data, (uint256));

        // Winners present => the full pool is held for terminal claims (nothing returned).
        assertEq(returnAmountWei, 0, "winners present: pool must be held, not returned");

        // 4a) Isolation: the regular round's selector at [X] is byte-for-byte unchanged.
        assertEq(
            uint64(uint256(vm.load(address(game), _offsetSlot(X)))),
            SENTINEL,
            "regular round offset [X] corrupted by terminal resolution"
        );

        // 4b) The terminal offsets landed at [X + 1], not [X].
        uint64 terminalOffsets = uint64(
            uint256(vm.load(address(game), _offsetSlot(X + 1)))
        );
        assertTrue(
            terminalOffsets != 0,
            "terminal offsets did not land at decBucketOffsetPacked[X + 1]"
        );
        assertTrue(
            terminalOffsets != SENTINEL,
            "terminal offsets unexpectedly equal the sentinel"
        );
    }
}
