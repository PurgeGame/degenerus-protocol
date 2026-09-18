// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {FFKeyHarness} from "./FarFutureSalvageSwap.t.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {SolvencyObligations} from "./helpers/SolvencyObligations.sol";

/// @title Exact-cost salvage boundary: an unfunded seller needs 1 wei of afking.
/// @dev At active level 90, selling 40 entries at level 110 with 100% jitter quotes
///      0.04 ETH: exactly one current entry, with no cash residual or extra funding. The
///      recycled ticket leg re-purchases from the seller's own (just-credited) claimable,
///      and that leg's cost exceeds the credited relabel by 1 wei, so a seller who starts
///      the swap with zero claimable and zero afking is short by exactly 1 wei and reverts
///      Insolvent. This is a documented boundary of the seller's own transaction — it costs
///      nothing to avoid (fund 1 wei of afking first, or hold any nonzero claimable) and is
///      trivially recoverable by retrying with that 1 wei funded — not a defect.
contract FarFutureSalvageSentinelEdgeTest is DeployProtocol {
    uint256 private constant BALANCES_PACKED_SLOT = 7; // claimable (low128) | afking (high128)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant TICKET_QUEUE_SLOT = 12;
    uint256 private constant TICKETS_OWED_PACKED_SLOT = 13;
    uint256 private constant CLAIMABLE_POOL_SLOT = 1;

    FFKeyHarness private ffk;
    address private seller;
    uint32[] private levels;
    uint256[] private qtys;
    uint256[] private idxs;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        ffk = new FFKeyHarness();
        vm.deal(address(game), 5_000 ether);
        _setLevel(89); // cl = 90 -> oneTicketWei = 0.16 ETH, oneEntryWei = 0.04 ETH
        _seedExactSwap(makeAddr("sentinel_seller"));
    }

    function _seedExactSwap(address who) internal {
        seller = who;
        _setExactJitter(who);

        // Seed the seller with 10 whole far-future tickets (40 entries) at level 110 (d=20 from cl=90).
        uint24 L = 110;
        uint24 key = ffk.ffKey(L);
        vm.store(address(game), _ownedPackedSlot(key, seller), bytes32(uint256(uint40(uint256(40) << 8))));
        bytes32 lenSlot = _queueBaseSlot(key);
        uint256 len = uint256(vm.load(address(game), lenSlot));
        vm.store(address(game), bytes32(uint256(keccak256(abi.encode(lenSlot))) + len), bytes32(uint256(uint160(seller))));
        vm.store(address(game), lenSlot, bytes32(len + 1));

        levels = new uint32[](1);
        qtys = new uint256[](1);
        idxs = new uint256[](1);
        levels[0] = uint32(L);
        qtys[0] = 40;
        idxs[0] = len;

        _seedClaimable(ContractAddresses.SDGNRS, 10 ether); // funds the buyer above the >=1 ETH floor
    }

    /// @notice A seller with zero claimable and zero afking is short exactly 1 wei on the
    ///         recycled ticket leg and reverts Insolvent. No player funds moved (revert unwinds).
    function test_SentinelEdge_ZeroClaimableZeroAfking_RevertsInsolvent() public {
        (, uint256 budget, uint256 ticketWei, uint256 cashWei,) =
            game.previewSellFarFutureEntries(seller, levels, qtys);
        assertEq(budget, 0.04 ether, "fixture: exact sale budget");
        assertEq(ticketWei, budget, "fixture: all value buys tickets");
        assertEq(cashWei, 0, "fixture: no cash residual");
        assertEq(game.claimableWinningsOf(seller), 0, "fixture: seller starts unfunded");
        assertEq(game.afkingFundingOf(seller), 0, "fixture: seller starts with no afking");

        vm.prank(seller);
        vm.expectRevert(DegenerusGameStorage.Insolvent.selector);
        game.sellFarFutureEntries(seller, levels, qtys, idxs);

        assertEq(_ownedEntries(seller, 110), 40, "far entries untouched by the reverted swap");
    }

    /// @notice The same seller funded with exactly 1 wei of afking clears the boundary: the
    ///         swap succeeds and the far entries are fully sold.
    function test_SentinelEdge_OneWeiAfking_SucceedsAndClearsFarEntries() public {
        _seedAfking(seller, 1);

        vm.prank(seller);
        game.sellFarFutureEntries(seller, levels, qtys, idxs);

        assertEq(_ownedEntries(seller, 110), 0, "far entries fully sold");
        uint256 queued = uint256(vm.load(address(game), _ownedPackedSlot(90, seller)));
        assertEq(uint32(queued >> 8), 1, "one complete current-level entry minted");
    }

    function test_NonSellingSinksCannotBeSoldByAnotherCaller() public {
        address[2] memory sinks = [ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        for (uint256 i; i < sinks.length; ++i) {
            vm.prank(seller);
            vm.expectRevert(DegenerusGame.NotApproved.selector);
            game.sellFarFutureEntries(sinks[i], levels, qtys, idxs);
        }
    }

    // --- helpers ---

    function _setExactJitter(address who) internal {
        for (uint256 i = 1; i < 200_000; ++i) {
            uint256 word = uint256(keccak256(abi.encodePacked("sentinel", i)));
            if (_jitterMult(who, word) == 10000) {
                _setPriorDayRngWord(word);
                return;
            }
        }
        fail("could not find a 100% jitter word");
    }

    function _setLevel(uint24 lvl) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFFFFFF) << 96;
        vm.store(address(game), bytes32(uint256(0)), bytes32((slot0 & ~mask) | (uint256(lvl) << 96)));
    }

    function _packedSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, BALANCES_PACKED_SLOT));
    }

    function _seedClaimable(address who, uint256 amt) internal {
        uint256 packed = uint256(vm.load(address(game), _packedSlot(who)));
        uint256 prevLow = uint128(packed);
        vm.store(address(game), _packedSlot(who), bytes32((packed & ~uint256(type(uint128).max)) | amt));
        _bumpPool(amt, prevLow);
    }

    function _seedAfking(address who, uint256 amt) internal {
        uint256 packed = uint256(vm.load(address(game), _packedSlot(who)));
        uint256 prevHigh = packed >> 128;
        vm.store(address(game), _packedSlot(who), bytes32((amt << 128) | uint128(packed)));
        _bumpPool(amt, prevHigh);
    }

    function _bumpPool(uint256 newAmt, uint256 prevAmt) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(CLAIMABLE_POOL_SLOT)));
        uint256 lower = w & uint256(type(uint128).max);
        uint256 pool = w >> 128;
        pool = newAmt >= prevAmt ? pool + (newAmt - prevAmt) : pool - (prevAmt - newAmt);
        vm.store(address(game), bytes32(CLAIMABLE_POOL_SLOT), bytes32((pool << 128) | lower));
    }

    function _setPriorDayRngWord(uint256 word) internal {
        uint32 day = game.currentDayView();
        vm.store(address(game), keccak256(abi.encode(uint256(day - 1), RNG_WORD_BY_DAY_SLOT)), bytes32(word));
    }

    function _jitterMult(address player, uint256 priorDayWord) internal pure returns (uint256) {
        return 7000 + (uint256(keccak256(abi.encodePacked(player, priorDayWord))) % 4001);
    }

    function _ownedPackedSlot(uint24 key, address who) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(key), TICKETS_OWED_PACKED_SLOT));
        return keccak256(abi.encode(who, uint256(inner)));
    }

    function _queueBaseSlot(uint24 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(key), TICKET_QUEUE_SLOT));
    }

    function _ownedEntries(address who, uint24 L) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), _ownedPackedSlot(ffk.ffKey(L), who))) >> 8);
    }
}
