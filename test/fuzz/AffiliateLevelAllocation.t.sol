// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title AffiliateLevelAllocation -- level-end affiliate sDGNRS through the real transition.
/// @notice At the level increment the game pays the level's top affiliate 0.5% of the Affiliate
///         pool, then records 2.5% of the remainder as the level's claim pot. Allocation is not a
///         transfer; affiliates claim their score share of it. Driven through the real game,
///         advance and claim paths.
contract AffiliateLevelAllocation is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    uint256 private constant POOL_HALF_MASK = (uint256(1) << 128) - 1;
    bytes32 private constant TOP_REWARD_SIG = keccak256("AffiliateDgnrsReward(address,uint24,uint256)");
    bytes32 private constant ALLOCATED_SIG = keccak256("LevelDgnrsAllocated(uint24,uint256)");

    bytes32 private constant CODE_ALICE = bytes32("ALICE_L");
    bytes32 private constant CODE_BOB = bytes32("BOB_L");

    address private alice;
    address private bob;
    address private buyer;
    uint256 private buyerNonce;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        alice = makeAddr("level_alloc_alice");
        bob = makeAddr("level_alloc_bob");
        buyer = makeAddr("level_alloc_buyer");
        vm.deal(buyer, 50_000 ether);
        vm.deal(address(game), 100_000 ether);
        vm.prank(alice);
        affiliate.createAffiliateCode(CODE_ALICE, 0);
        vm.prank(bob);
        affiliate.createAffiliateCode(CODE_BOB, 0);
    }

    function test_LevelEndPaysHalfPercentTopAndRecordsTwoAndAHalfPercentPot() public {
        for (uint256 i; i < 3; ++i) _buyWithCode(CODE_ALICE);
        _buyWithCode(CODE_BOB);
        uint256 aliceScore = affiliate.affiliateScore(1, game.walletIdOf(alice));
        uint256 bobScore = affiliate.affiliateScore(1, game.walletIdOf(bob));
        assertGt(aliceScore, bobScore, "fixture: alice leads level 1");
        assertGt(bobScore, 0, "fixture: bob also scored");

        (address top, uint256 paid, uint256 allocation, uint256 poolAfter) = _driveToLevelOne();
        assertEq(top, alice, "the level leader is paid");
        uint256 poolBefore = poolAfter + paid;
        assertGt(poolBefore, 0, "fixture: funded Affiliate pool");
        assertEq(paid, poolBefore * 50 / 10_000, "top affiliate receives 0.5% of the pool");
        assertEq(allocation, poolAfter * 250 / 10_000, "claim pot is 2.5% of the remainder");

        uint256 total = affiliate.totalAffiliateScore(1);
        uint256 beforeClaim = sdgnrs.balanceOf(bob);
        vm.prank(bob);
        game.claimAffiliateDgnrs(address(0));
        assertEq(sdgnrs.balanceOf(bob) - beforeClaim, allocation * bobScore / total, "score share of the pot");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Affiliate), poolAfter - allocation * bobScore / total,
            "only the claim moves the pot's tokens");
    }

    function test_CodelessBuysMakeTheVaultTheLevelLeaderAtTheSameRates() public {
        (address top, uint256 paid, uint256 allocation, uint256 poolAfter) = _driveToLevelOne();
        assertEq(top, ContractAddresses.VAULT, "codeless buys score the default affiliate");
        assertEq(paid, (poolAfter + paid) * 50 / 10_000, "top affiliate receives 0.5% of the pool");
        assertEq(allocation, poolAfter * 250 / 10_000, "claim pot is 2.5% of the remainder");
    }

    // ---- helpers ----

    function _buyWithCode(bytes32 code) private {
        address who = address(uint160(0xA11C0000 + buyerNonce++));
        vm.deal(who, 5 ether);
        vm.prank(who);
        game.purchase{value: 1.01 ether}(who, 400, BoxOrderLib.boCustomFloor(1 ether), code, MintPaymentKind.DirectEth, false);
    }

    /// @dev Drive the real game to level 1 and read the transition's affiliate events. The
    ///      Affiliate pool is read right after the increment, before any claim.
    function _driveToLevelOne()
        private
        returns (address top, uint256 paid, uint256 allocation, uint256 poolAfter)
    {
        vm.recordLogs();
        uint256 simTime = block.timestamp;
        bool allocated;
        for (uint256 day; day < 500 && game.level() < 1; ++day) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(500 ether);
            _buyTickets(4000);
            for (uint256 j; j < 80 && game.level() < 1; ++j) {
                _fulfillVrfIfPending();
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
                if (!ok) break;
            }
        }
        assertEq(game.level(), 1, "reached level 1");
        poolAfter = sdgnrs.poolBalance(sDGNRS.Pool.Affiliate);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == TOP_REWARD_SIG && uint256(logs[i].topics[2]) == 1) {
                top = address(uint160(uint256(logs[i].topics[1])));
                paid = abi.decode(logs[i].data, (uint256));
            } else if (logs[i].topics[0] == ALLOCATED_SIG && uint256(logs[i].topics[1]) == 1) {
                allocation = abi.decode(logs[i].data, (uint256));
                allocated = true;
            }
        }
        assertTrue(allocated, "the transition recorded the level pot");
    }

    function _seedNextPrizePool(uint256 targetNext) private {
        uint256 packed = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT)));
        if ((packed & POOL_HALF_MASK) >= targetNext) return;
        vm.store(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT), bytes32((packed & ~POOL_HALF_MASK) | targetNext));
    }

    function _buyTickets(uint256 qty) private {
        (,,, bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        vm.prank(buyer);
        try game.purchase{value: cost}(buyer, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrfIfPending() private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(keccak256(abi.encode(block.timestamp, game.level(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }
}
