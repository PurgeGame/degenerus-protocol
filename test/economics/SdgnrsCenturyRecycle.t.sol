// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RedemptionCloseTools} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Chosen-roll accounting fixture: explicitly supplies the completed ticket
///      prerequisites and the same published session lifecycle that live settlement requires.
///      The production engine reachability is covered by AutomaticRedemptionSettlement.
contract CenturyRedemptionSessionFixture is DegenerusGame {
    function publishRedemptionSession(uint24 day, uint256 word) external {
        dailyIdx = day;
        rngWordCurrent = word;
        rngLockedFlag = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
    }
}

contract SdgnrsCenturyRecycleTest is RedemptionCloseTools {
    uint256 private constant INITIAL = 1e24;
    uint256 private constant RNG_WORD = 53; // 50% at level 100; other centuries use separate draws.
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    receive() external payable {}

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _primeCurrentDayRng();
        _giveWalletId(ALICE);
        _giveWalletId(BOB);
        _giveWalletId(ContractAddresses.CREATOR);
        // Custody-backed redemptions exercise the real reservation gate without game-ledger mocks.
        vm.deal(address(sdgnrs), 100 ether);
    }

    function _assertAdmissibleBurn(uint256 amount) private view {
        (uint256 value,) = sdgnrs.previewBurnValue(amount);
        assertGe(value, sdgnrs.MIN_REDEMPTION_VALUE(), "fixture: burn meets admission minimum");
    }

    function _recycle(uint24 lvl) private {
        _recycle(lvl, RNG_WORD);
    }

    function _recycle(uint24 lvl, uint256 rngWord) private {
        vm.prank(address(game));
        sdgnrs.recycleCentury(lvl, rngWord);
    }

    function _refillPercent(uint24 lvl, uint256 rngWord) private pure returns (uint256) {
        return 25 + uint256(keccak256(abi.encode(
            rngWord, uint256(keccak256("sdgnrs.century.refill")) ^ uint256(lvl)
        ))) % 51;
    }

    function _award(sDGNRS.Pool pool, address recipient, uint256 amount) private returns (uint256) {
        vm.prank(address(game));
        return sdgnrs.transferFromPool(pool, recipient, amount);
    }

    /// @dev One Redemption-stage step as mineFlip dispatches it (the live worker, called as the
    ///      Game) at the smallest allowance (10k steps) that moves the cohort: it settles exactly
    ///      the FIFO head. Probed on snapshots, then applied.
    function _settleOneClaim() private {
        (,,uint32 cursor,) = sdgnrs.redemptionBatchState();
        for (uint256 g = 500_000; g <= 9_000_000; g += 10_000) {
            uint256 snap = vm.snapshotState();
            vm.prank(address(game));
            sdgnrs.runRedemptionWork(batchWord, g);
            bool moved = _cursor() != cursor
                || !sdgnrs.redemptionSettlementPending();
            assertTrue(vm.revertToState(snap));
            if (moved) {
                vm.prank(address(game));
                sdgnrs.runRedemptionWork(batchWord, g);
                assertTrue(
                    _cursor() == cursor + 1
                        || !sdgnrs.redemptionSettlementPending(),
                    "harness: the step consumed exactly the FIFO head"
                );
                return;
            }
        }
        revert("harness: no allowance settles a beneficiary");
    }

    function _cursor() private view returns (uint32 cursor) { (,,cursor,) = sdgnrs.redemptionBatchState(); }

    function _pools() private view returns (uint256[5] memory amounts) {
        for (uint8 i; i < 5; ++i) amounts[i] = sdgnrs.poolBalance(sDGNRS.Pool(i));
    }

    function _sum(uint256[5] memory amounts) private pure returns (uint256 total) {
        for (uint8 i; i < 5; ++i) total += amounts[i];
    }

    function _assertRefill(uint24 lvl, uint256 burned) private {
        _assertRefill(lvl, burned, RNG_WORD);
    }

    struct RefillSnapshot { uint256 supply; uint256 checkpoint; uint256 inventory; uint256 wrapper; uint256 wrapperSupply; uint256 voting; }

    function _assertRefill(uint24 lvl, uint256 burned, uint256 rngWord) private {
        this.checkRefill(lvl, burned, rngWord);
    }

    // External test helper prevents the optimizer from inlining this full accounting
    // oracle into every century of the long fuzz loop.
    function checkRefill(uint24 lvl, uint256 burned, uint256 rngWord) external {
        RefillSnapshot memory prior;
        prior.supply = sdgnrs.totalSupply();
        prior.checkpoint = sdgnrs.centurySupplyCheckpoint();
        prior.inventory = sdgnrs.balanceOf(address(sdgnrs));
        prior.wrapper = sdgnrs.balanceOf(address(dgnrs));
        prior.wrapperSupply = dgnrs.totalSupply();
        prior.voting = sdgnrs.votingSupply();
        uint256[5] memory beforePools = _pools();
        uint256 percent = _refillPercent(lvl, rngWord);
        uint256 mint = burned * percent / 100;
        assertGe(mint, burned * 25 / 100);
        assertLe(mint, burned * 75 / 100);
        uint256 whale = mint / 7;
        uint256 affiliateShare = mint * 3 / 7;
        uint256 lootbox = mint - 2 * whale - affiliateShare;

        vm.expectEmit(true, false, false, true, address(sdgnrs));
        emit sDGNRS.CenturyRecycled(lvl, percent, burned, mint, whale, affiliateShare, lootbox, whale);
        _recycle(lvl, rngWord);

        uint256[5] memory afterPools = _pools();
        assertEq(afterPools[0] - beforePools[0], whale);
        assertEq(afterPools[1] - beforePools[1], affiliateShare);
        assertEq(afterPools[2] - beforePools[2], lootbox);
        assertEq(afterPools[3] - beforePools[3], whale);
        assertEq(afterPools[4], beforePools[4], "presale never refilled");
        assertEq(_sum(afterPools) - _sum(beforePools), mint, "pool credits conserve the mint");
        assertEq(sdgnrs.balanceOf(address(sdgnrs)) - prior.inventory, mint, "prior.inventory funded exactly once");
        assertEq(sdgnrs.balanceOf(address(sdgnrs)) - _sum(afterPools), prior.inventory - _sum(beforePools));
        assertEq(sdgnrs.totalSupply(), prior.supply + mint);
        assertEq(sdgnrs.centurySupplyCheckpoint(), prior.checkpoint - burned + mint, "prior.checkpoint includes unpriced holder escrow");
        assertLe(sdgnrs.totalSupply(), prior.checkpoint);
        assertLe(sdgnrs.totalSupply(), INITIAL);
        assertEq(sdgnrs.lastRecycledCentury(), lvl / 100);
        assertEq(sdgnrs.votingSupply(), prior.voting, "excluded pool prior.inventory offsets new prior.supply");
        assertEq(sdgnrs.balanceOf(address(dgnrs)), prior.wrapper);
        assertEq(dgnrs.totalSupply(), prior.wrapperSupply);
    }

    function testInitialCheckpointAndOnlyGame() public {
        assertEq(sdgnrs.centurySupplyCheckpoint(), INITIAL);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        assertFalse(sdgnrs.recyclingClosed());
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.recycleCentury(100, RNG_WORD);
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
        _award(sDGNRS.Pool.Reward, address(sdgnrs), 1e12 + 1);
        _assertRefill(300, 1e12 + 1);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 2e12 + 1);
        uint256 supply = sdgnrs.totalSupply();
        _recycle(100);
        _recycle(200);
        _recycle(300);
        assertEq(sdgnrs.totalSupply(), supply, "earlier boundaries cannot reissue burns");
        _assertRefill(500, 2e12 + 1);
    }

    function testZeroBurnAndFractionalDustStillAdvanceCheckpoint() public {
        _assertRefill(100, 0);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 1);
        _recycle(100);
        assertEq(sdgnrs.totalSupply(), INITIAL - 1);
        _assertRefill(200, 1);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 1);
        _assertRefill(300, 1);
        assertEq(sdgnrs.totalSupply(), INITIAL - 2, "fractional dust never rolls into the next budget");
    }

    function testFuzzAllocationAndRounding(uint256 requested, uint256 rngWord) public {
        uint256 amount = bound(requested, 0, INITIAL / 10);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), amount);
        _assertRefill(100, amount, rngWord);
    }

    function testMinimumRollMints25Percent() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 100e12);
        _assertRefill(100, 100e12, 8);
        assertEq(sdgnrs.totalSupply(), INITIAL - 75e12);
    }

    function testMaximumRollMints75PercentAndCannotReroll() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 100e12);
        _assertRefill(100, 100e12, 119);
        assertEq(sdgnrs.totalSupply(), INITIAL - 25e12);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 100e12);
        vm.warp(block.timestamp + 3 days);
        vm.recordLogs();
        _recycle(100, 8);
        _recycle(100, type(uint256).max);
        assertEq(vm.getRecordedLogs().length, 0, "replays emit no new roll or mint");
        assertEq(sdgnrs.totalSupply(), INITIAL - 125e12);
        assertEq(sdgnrs.centurySupplyCheckpoint(), INITIAL - 25e12);
    }

    function testSameWordSeparatesCenturies() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 100e12);
        _assertRefill(100, 100e12, 8);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 100e12);
        _assertRefill(200, 100e12, 8);
        assertEq(sdgnrs.totalSupply(), INITIAL - 114e12, "25% then 61% for the same word");
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
        assertEq(_award(sDGNRS.Pool.Whale, address(sdgnrs), 1e12), 0);
        _assertRefill(100, actual);
    }

    function testMixedRedemptionsWrappedBurnsAndTransfers() public {
        uint256 direct = 1_000e18 + 3;
        uint256 wrapped = 2_000e18 + 5;
        uint256 selfBurn = 3_000e18 + 7;
        _award(sDGNRS.Pool.Reward, ALICE, direct * 2);
        _assertAdmissibleBurn(direct);
        vm.prank(ALICE);
        sdgnrs.burn(direct);
        uint256 wrapperBefore = dgnrs.totalSupply();
        _assertAdmissibleBurn(wrapped);
        vm.prank(ContractAddresses.VAULT);
        sdgnrs.burnWrapped(wrapped);
        assertEq(dgnrs.totalSupply(), wrapperBefore - wrapped);
        _award(sDGNRS.Pool.Affiliate, address(sdgnrs), selfBurn);
        _award(sDGNRS.Pool.Lootbox, BOB, 4_000e18);
        _unwrapFromVault(BOB, 5_000e18);
        vm.prank(ALICE);
        vm.expectRevert(sDGNRS.Insufficient.selector);
        sdgnrs.burn(type(uint256).max);
        _closeFunded();
        _assertRefill(100, direct + wrapped + selfBurn);
        assertEq(sdgnrs.balanceOf(ALICE), direct);
        assertEq(sdgnrs.balanceOf(BOB), 9_000e18, "ordinary transfers and unwraps are not burns");
    }

    function testUnwrappedInventorySurplusIsPreserved() public {
        _unwrapFromVault(address(sdgnrs), 1_000e12);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 101e12);
        _assertRefill(100, 101e12);
        assertEq(sdgnrs.balanceOf(address(sdgnrs)) - _sum(_pools()), 1_000e12);
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
            allMinted += burned * _refillPercent(century * 100, seed) / 100;
            _assertRefill(century * 100, burned, seed);
            assertEq(sdgnrs.totalSupply(), INITIAL + allMinted - allBurned);
            assertLe(allMinted * 100, allBurned * 75);
        }
    }

    function _fundFlip() private {
        bytes32 slot = keccak256(abi.encode(uint32(2), uint256(2)));
        uint256 packed = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((packed & (type(uint256).max << 128)) | uint128(1e24)));
    }

    function _pendingFingerprint(uint32 id) private view returns (bytes32) {
        (uint128 at,uint16 ascore) = sdgnrs.pendingRedemptions(game.walletIdOf(ALICE), id);
        (uint128 bt,uint16 bscore) = sdgnrs.pendingRedemptions(game.walletIdOf(BOB), id);
        (uint128 t,uint128 supply,uint96 base,uint96 escrow,uint16 roll,uint16 reward) = sdgnrs.redemptionBatches(id);
        return keccak256(abi.encode(at, ascore, bt, bscore, t, supply, base, escrow, roll, reward,
            sdgnrs.pendingRedemptionEthValue(), address(sdgnrs).balance, mockStETH.balanceOf(address(sdgnrs)),
            game.claimableWinningsOf(address(sdgnrs)), sdgnrs.flipReserve()));
    }
    function testPendingAndResolvedClaimsSurviveRefillsAndSettle() public {
        _fundFlip();
        mockStETH.mint(address(sdgnrs), 50 ether);
        _award(sDGNRS.Pool.Reward, ALICE, 10_000e18);
        _award(sDGNRS.Pool.Reward, BOB, 10_000e18);
        uint32 id = _openBatch();
        _assertAdmissibleBurn(1_000e18 + 1);
        vm.prank(ALICE); sdgnrs.burn(1_000e18 + 1);
        _assertAdmissibleBurn(2_000e18 + 1);
        vm.prank(BOB); sdgnrs.burn(2_000e18 + 1);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        bytes32 fingerprint = _pendingFingerprint(id);
        _assertRefill(100, 0); // Open burns retain their economic holder share.
        assertEq(_pendingFingerprint(id), fingerprint);
        _resolveTestBatch(id, 175);
        uint256 baseAlice = _batchBase(ALICE, id);
        assertGt(baseAlice, 0);
        (,,,uint96 escrow,,) = sdgnrs.redemptionBatches(id);
        assertGt(escrow, 0);
        uint256 reserve = sdgnrs.pendingRedemptionEthValue();
        (uint80 batchTokens, uint96 batchPayout,,,,) = sdgnrs.redemptionBatches(id);
        (uint80 aliceTokens,) = sdgnrs.pendingRedemptions(game.walletIdOf(ALICE), id);
        uint256 alicePayout = uint256(batchPayout) * aliceTokens / batchTokens;
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 7_000e18);
        fingerprint = _pendingFingerprint(id);
        _assertRefill(200, 10_000e18 + 2); // The close now counts both live burns.
        assertEq(_pendingFingerprint(id), fingerprint);
        uint256 supply = sdgnrs.totalSupply();
        uint256 before = game.claimableWinningsOf(ALICE);
        _settleOneClaim();
        (uint128 waiting,) = sdgnrs.pendingRedemptions(game.walletIdOf(BOB), id);
        assertGt(waiting, 0);
        assertApproxEqAbs(game.claimableWinningsOf(ALICE) - before, baseAlice * 175 / 100 / 2, 1);
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserve - alicePayout);
        _settleOneClaim();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertEq(sdgnrs.totalSupply(), supply);
        _assertRefill(300, 0);
    }
    function testOpenBatchRemainsUnpricedAcrossRefill() public {
        _award(sDGNRS.Pool.Reward, ALICE, 3_000e18);
        uint32 id = _openBatch();
        _assertAdmissibleBurn(1_000e18 + 1);
        vm.prank(ALICE); sdgnrs.burn(1_000e18 + 1);
        (,uint96 payout,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(payout, 0);
        _assertRefill(100, 0);
        _assertAdmissibleBurn(1_000e18 + 1);
        vm.prank(ALICE); sdgnrs.burn(1_000e18 + 1);
        (uint80 tokens,uint96 afterPayout,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(afterPayout, 0);
        assertEq(tokens, 2_000e18 + 2);
        _assertRefill(200, 0);
    }

    function _endGame() private {
        vm.warp(block.timestamp + 400 days);
        for (uint256 i; i < 240 && !game.gameOver(); ++i) {
            if (game.advanceDue() || game.rngLocked()) {
                try game.mineFlip(0) {} catch {}
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
        _award(sDGNRS.Pool.Reward, ALICE, 1_000e12);
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 10_000e12);
        _endGame();
        uint256 supply = sdgnrs.totalSupply();
        vm.prank(ALICE);
        sdgnrs.burn(1_000e12);
        vm.prank(ContractAddresses.VAULT);
        sdgnrs.burnWrapped(1_000e12);
        _recycle(100);
        _recycle(200);
        assertEq(sdgnrs.totalSupply(), supply - 2_000e12);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        assertEq(_sum(_pools()), 0);
    }

    function testGameOverAfterRefillNeverMintsAgain() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 101e12);
        _assertRefill(100, 101e12);
        _endGame();
        uint256 supply = sdgnrs.totalSupply();
        _recycle(200);
        _recycle(300);
        assertEq(sdgnrs.totalSupply(), supply);
        assertEq(sdgnrs.lastRecycledCentury(), 1);
    }

    function testZeroInventoryTerminalEarlyReturnStillCloses() public {
        _award(sDGNRS.Pool.Whale, address(sdgnrs), 1e12);
        for (uint8 i; i < 5; ++i) _award(sDGNRS.Pool(i), ALICE, type(uint256).max);
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), 0);
        vm.prank(address(game));
        sdgnrs.burnAtGameOver();
        assertTrue(sdgnrs.recyclingClosed());
        _recycle(100);
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        assertEq(sdgnrs.totalSupply(), INITIAL - 1e12);
    }
}
