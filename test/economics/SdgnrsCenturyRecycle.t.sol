// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract SdgnrsCenturyRecycleTest is DeployProtocol {
    uint256 private constant INITIAL = 1e30;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    receive() external payable {}

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _primeCurrentDayRng();
        // Custody-backed redemptions exercise the real reservation gate without game-ledger mocks.
        vm.deal(address(sdgnrs), 100 ether);
    }

    function _recycle(uint24 lvl) private {
        vm.prank(address(game));
        sdgnrs.recycleCentury(lvl);
    }

    function _award(sDGNRS.Pool pool, address recipient, uint256 amount) private returns (uint256) {
        vm.prank(address(game));
        return sdgnrs.transferFromPool(pool, recipient, amount);
    }

    function _pools() private view returns (uint256[5] memory amounts) {
        for (uint8 i; i < 5; ++i) amounts[i] = sdgnrs.poolBalance(sDGNRS.Pool(i));
    }

    function _sum(uint256[5] memory amounts) private pure returns (uint256 total) {
        for (uint8 i; i < 5; ++i) total += amounts[i];
    }

    function _assertRefill(uint24 lvl, uint256 burned) private {
        uint256 supply = sdgnrs.totalSupply();
        uint256 checkpoint = sdgnrs.centurySupplyCheckpoint();
        uint256 inventory = sdgnrs.balanceOf(address(sdgnrs));
        uint256 wrapper = sdgnrs.balanceOf(address(dgnrs));
        uint256 wrapperSupply = dgnrs.totalSupply();
        uint256 voting = sdgnrs.votingSupply();
        uint256[5] memory beforePools = _pools();
        uint256 mint = burned / 2;
        uint256 whale = mint / 7;
        uint256 affiliateShare = mint * 3 / 7;
        uint256 lootbox = mint - 2 * whale - affiliateShare;

        vm.expectEmit(true, false, false, true, address(sdgnrs));
        emit sDGNRS.CenturyRecycled(lvl, burned, mint, whale, affiliateShare, lootbox, whale);
        _recycle(lvl);

        uint256[5] memory afterPools = _pools();
        assertEq(afterPools[0] - beforePools[0], whale);
        assertEq(afterPools[1] - beforePools[1], affiliateShare);
        assertEq(afterPools[2] - beforePools[2], lootbox);
        assertEq(afterPools[3] - beforePools[3], whale);
        assertEq(afterPools[4], beforePools[4], "presale never refilled");
        assertEq(_sum(afterPools) - _sum(beforePools), mint, "pool credits conserve the mint");
        assertEq(sdgnrs.balanceOf(address(sdgnrs)) - inventory, mint, "inventory funded exactly once");
        assertEq(sdgnrs.balanceOf(address(sdgnrs)) - _sum(afterPools), inventory - _sum(beforePools));
        assertEq(sdgnrs.totalSupply(), supply + mint);
        assertEq(sdgnrs.centurySupplyCheckpoint(), supply + mint, "checkpoint is POST mint");
        assertLe(sdgnrs.totalSupply(), checkpoint);
        assertLe(sdgnrs.totalSupply(), INITIAL);
        assertEq(sdgnrs.lastRecycledCentury(), lvl / 100);
        assertEq(sdgnrs.votingSupply(), voting, "excluded pool inventory offsets new supply");
        assertEq(sdgnrs.balanceOf(address(dgnrs)), wrapper);
        assertEq(dgnrs.totalSupply(), wrapperSupply);
    }

    function testInitialCheckpointAndOnlyGame() public {
        assertEq(sdgnrs.centurySupplyCheckpoint(), INITIAL);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        assertFalse(sdgnrs.recyclingClosed());
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.recycleCentury(100);
    }

    function testNonBoundariesAndDuplicateCallsDoNothing() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 101);
        uint256 supply = sdgnrs.totalSupply();
        _recycle(0);
        _recycle(99);
        _recycle(101);
        _recycle(199);
        assertEq(sdgnrs.totalSupply(), supply);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        _assertRefill(100, 101);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 201);
        supply = sdgnrs.totalSupply();
        _recycle(100);
        assertEq(sdgnrs.totalSupply(), supply, "repeat must not recycle new-century burns");
        _assertRefill(200, 201);
        _recycle(100);
        assertEq(sdgnrs.lastRecycledCentury(), 2, "old boundary cannot roll back epoch");
    }

    function testLaterBoundaryConsumesCheckpointOnceWithoutCatchUpLoop() public {
        _award(sDGNRS.Pool.Reward, address(sdgnrs), 1 ether + 1);
        _assertRefill(300, 1 ether + 1);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 2 ether + 1);
        uint256 supply = sdgnrs.totalSupply();
        _recycle(100);
        _recycle(200);
        _recycle(300);
        assertEq(sdgnrs.totalSupply(), supply, "earlier boundaries cannot reissue burns");
        _assertRefill(500, 2 ether + 1);
    }

    function testZeroBurnAndOddDustStillAdvanceCheckpoint() public {
        _assertRefill(100, 0);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 1);
        _recycle(100);
        assertEq(sdgnrs.totalSupply(), INITIAL - 1);
        _assertRefill(200, 1);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 1);
        _assertRefill(300, 1);
        assertEq(sdgnrs.totalSupply(), INITIAL - 2, "odd dust never rolls into the next budget");
    }

    function testFuzzAllocationAndRounding(uint256 requested) public {
        uint256 amount = bound(requested, 0, INITIAL / 10);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), amount);
        _assertRefill(100, amount);
    }

    function testTinyRawUnitSplits() public {
        for (uint24 i; i < 30; ++i) {
            _award(sDGNRS.Pool.Whale, address(sdgnrs), i);
            _assertRefill((i + 1) * 100, i);
        }
    }

    function testClampedSelfAwardCountsActualBurn() public {
        uint256 actual = _award(sDGNRS.Pool.Whale, address(sdgnrs), type(uint256).max);
        assertEq(actual, INITIAL / 10);
        assertEq(_award(sDGNRS.Pool.Whale, address(sdgnrs), 1 ether), 0);
        _assertRefill(100, actual);
    }

    function testMixedRedemptionsWrappedBurnsAndTransfers() public {
        uint256 direct = 1_000 ether + 3;
        uint256 wrapped = 2_000 ether + 5;
        uint256 selfBurn = 3_000 ether + 7;
        _award(sDGNRS.Pool.Reward, ALICE, direct * 2);
        vm.prank(ALICE);
        sdgnrs.burn(direct);
        uint256 wrapperBefore = dgnrs.totalSupply();
        vm.prank(ContractAddresses.CREATOR);
        sdgnrs.burnWrapped(wrapped);
        assertEq(dgnrs.totalSupply(), wrapperBefore - wrapped);
        _award(sDGNRS.Pool.Affiliate, address(sdgnrs), selfBurn);
        _award(sDGNRS.Pool.Lootbox, BOB, 4_000 ether);
        vm.prank(ContractAddresses.CREATOR);
        dgnrs.unwrapTo(BOB, 5_000 ether);
        vm.prank(ALICE);
        vm.expectRevert(sDGNRS.Insufficient.selector);
        sdgnrs.burn(type(uint256).max);
        _assertRefill(100, direct + wrapped + selfBurn);
        assertEq(sdgnrs.balanceOf(ALICE), direct);
        assertEq(sdgnrs.balanceOf(BOB), 9_000 ether, "ordinary transfers and unwraps are not burns");
    }

    function testUnwrappedInventorySurplusIsPreserved() public {
        vm.prank(ContractAddresses.CREATOR);
        dgnrs.unwrapTo(address(sdgnrs), 1_000 ether);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 101 ether);
        _assertRefill(100, 101 ether);
        assertEq(sdgnrs.balanceOf(address(sdgnrs)) - _sum(_pools()), 1_000 ether);
    }

    function testEmptyPoolsAndInventoryCanBeRefilled() public {
        uint256 burns;
        for (uint8 i; i < 4; ++i) burns += _award(sDGNRS.Pool(i), address(sdgnrs), type(uint256).max);
        _award(sDGNRS.Pool.PresaleBox, ALICE, type(uint256).max);
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), 0);
        _assertRefill(100, burns);
    }

    function testFuzzManyCenturiesConserveSupply(uint256 seed) public {
        uint256 allBurned;
        uint256 allMinted;
        for (uint24 century = 1; century <= 25; ++century) {
            uint256 burned;
            for (uint8 p; p < 4; ++p) {
                seed = uint256(keccak256(abi.encode(seed, century, p)));
                uint256 amount = seed % (sdgnrs.poolBalance(sDGNRS.Pool(p)) + 1);
                burned += _award(sDGNRS.Pool(p), address(sdgnrs), amount);
            }
            allBurned += burned;
            allMinted += burned / 2;
            _assertRefill(century * 100, burned);
            assertEq(sdgnrs.totalSupply(), INITIAL + allMinted - allBurned);
            assertLe(allMinted * 2, allBurned);
        }
    }

    function _fundFlip() private {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), uint256(2)));
        uint256 packed = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((packed & (type(uint256).max << 128)) | uint128(1e30)));
    }

    function _claimSlot(address who, uint24 day) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(day), keccak256(abi.encode(who, uint256(5)))));
    }

    function _pendingFingerprint(uint24 day) private view returns (bytes32) {
        // Include both neighboring lanes of slot 0, full day cap/base, claims, resolution,
        // real ETH/stETH custody, game claimable and FLIP backing. Only supply may change.
        return keccak256(abi.encode(
            uint256(vm.load(address(sdgnrs), bytes32(0))) >> 128,
            vm.load(address(sdgnrs), keccak256(abi.encode(uint256(day), uint256(7)))),
            vm.load(address(sdgnrs), _claimSlot(ALICE, day)),
            vm.load(address(sdgnrs), _claimSlot(BOB, day)),
            sdgnrs.redemptionPeriods(day),
            address(sdgnrs).balance,
            mockStETH.balanceOf(address(sdgnrs)),
            game.claimableWinningsOf(address(sdgnrs)),
            sdgnrs.flipReserve()
        ));
    }

    function testPendingAndResolvedClaimsSurviveRefillsAndSettle() public {
        _fundFlip();
        mockStETH.mint(address(sdgnrs), 50 ether);
        _award(sDGNRS.Pool.Reward, ALICE, 10_000 ether);
        _award(sDGNRS.Pool.Reward, BOB, 10_000 ether);
        uint24 day = game.currentDayView();
        vm.prank(ALICE);
        sdgnrs.burn(1_000 ether + 1);
        vm.prank(BOB);
        sdgnrs.burn(2_000 ether + 1);
        (uint96 baseAlice,, uint96 escrowAlice) = sdgnrs.pendingRedemptions(ALICE, day);
        assertGt(baseAlice, 0);
        assertGt(escrowAlice, 0);
        assertEq(sdgnrs.pendingResolveDay(), day);
        assertGt(sdgnrs.pendingRedemptionEthValue(), 0);
        bytes32 fingerprint = _pendingFingerprint(day);
        _assertRefill(100, 3_000 ether + 2);
        assertEq(_pendingFingerprint(day), fingerprint, "unresolved claims and packed neighbors preserved");

        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(175, day);
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 7_000 ether);
        fingerprint = _pendingFingerprint(day);
        _assertRefill(200, 7_000 ether);
        assertEq(_pendingFingerprint(day), fingerprint, "resolved claims preserved");

        // Existing claims retain their fixed base/escrow. Small ETH awards intentionally take
        // the real dust-box forfeit path. A recorded winning flip exercises the real FLIP credit.
        bytes32 resultSlot = keccak256(abi.encode(uint256((day + 1) >> 5), uint256(1)));
        uint256 shift = (uint256(day + 1) & 31) * 8;
        uint256 result = uint256(vm.load(address(coinflip), resultSlot));
        vm.store(address(coinflip), resultSlot, bytes32((result & ~(uint256(255) << shift)) | (uint256(100) << shift)));
        uint256 supply = sdgnrs.totalSupply();
        uint256 beforeClaimable = game.claimableWinningsOf(ALICE);
        vm.prank(BOB); // live-game resolution stays permissionless
        sdgnrs.claimRedemption(ALICE, day);
        uint256 expectedDirect = uint256(baseAlice) * 175 / 100 / 2;
        // Game's claimable ledger initializes a 1-wei dust sentinel on its first credit.
        uint256 credited = game.claimableWinningsOf(ALICE) - beforeClaimable;
        assertGe(credited, expectedDirect);
        assertLe(credited, expectedDirect + 1);
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved - uint256(baseAlice) * 175 / 100);
        sdgnrs.claimRedemption(BOB, day);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(sdgnrs.totalSupply(), supply, "settling a burn is not another supply reduction");
        _assertRefill(300, 0);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        sdgnrs.claimRedemption(ALICE, day);
    }

    function testExistingDailyCapIsNotResetByRefill() public {
        _award(sDGNRS.Pool.Reward, ALICE, 3_000 ether);
        vm.prank(ALICE);
        sdgnrs.burn(1_000 ether + 1);
        uint24 day = game.currentDayView();
        bytes32 slot = keccak256(abi.encode(uint256(day), uint256(7)));
        uint256 beforeDay = uint256(vm.load(address(sdgnrs), slot));
        _recycle(100);
        vm.prank(ALICE);
        sdgnrs.burn(1_000 ether + 1);
        uint256 afterDay = uint256(vm.load(address(sdgnrs), slot));
        assertEq(uint64(afterDay >> 64), uint64(beforeDay >> 64), "original daily supply snapshot survives");
        assertEq(uint64(afterDay >> 128), uint64(beforeDay >> 128) + 1001, "rounded daily burns accumulate");
        _assertRefill(200, 1_000 ether + 1);
    }

    function _endGame() private {
        vm.warp(block.timestamp + 400 days);
        for (uint256 i; i < 240 && !game.gameOver(); ++i) {
            if (game.advanceDue() || game.rngLocked()) {
                try game.advanceGame() {} catch {}
            }
            uint256 req = mockVRF.lastRequestId();
            if (req != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(req);
                if (!fulfilled) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode(i))) | 1);
            }
        }
        assertTrue(game.gameOver(), "real terminal drain reached");
        assertTrue(sdgnrs.recyclingClosed());
    }

    function testRealGameOverClosesRecyclingAndTerminalBurnsNeverRecycle() public {
        _award(sDGNRS.Pool.Reward, ALICE, 1_000 ether);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 10_000 ether);
        _endGame();
        uint256 supply = sdgnrs.totalSupply();
        vm.prank(ALICE);
        sdgnrs.burn(1_000 ether);
        vm.prank(ContractAddresses.CREATOR);
        sdgnrs.burnWrapped(1_000 ether);
        _recycle(100);
        _recycle(200);
        assertEq(sdgnrs.totalSupply(), supply - 2_000 ether);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        assertEq(_sum(_pools()), 0);
    }

    function testGameOverAfterRefillNeverMintsAgain() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 101 ether);
        _assertRefill(100, 101 ether);
        _endGame();
        uint256 supply = sdgnrs.totalSupply();
        _recycle(200);
        _recycle(300);
        assertEq(sdgnrs.totalSupply(), supply);
        assertEq(sdgnrs.lastRecycledCentury(), 1);
    }

    function testZeroInventoryTerminalEarlyReturnStillCloses() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 1 ether);
        for (uint8 i; i < 5; ++i) _award(sDGNRS.Pool(i), ALICE, type(uint256).max);
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), 0);
        vm.prank(address(game));
        sdgnrs.burnAtGameOver();
        assertTrue(sdgnrs.recyclingClosed());
        _recycle(100);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        assertEq(sdgnrs.totalSupply(), INITIAL - 1 ether);
    }
}
