// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusStonk} from "../../contracts/DegenerusStonk.sol";

/// @title AffiliateDgnrsClaim -- Tests for segregated affiliate DGNRS claim system
/// @notice Validates proportional distribution, claim window, and edge cases.
///
/// Strategy: tests that need claims use vm.store to set levelDgnrsAllocation
/// directly (slot 51), bypassing the complex game state machine for the
/// jackpot/transition flow. Score routing and totalAffiliateScore accumulation
/// are tested via actual purchases (no vm.store needed).
contract AffiliateDgnrsClaim is DeployProtocol {
    address alice;
    address bob;
    address carol;

    bytes32 constant CODE_ALICE = bytes32("ALICE");
    bytes32 constant CODE_BOB   = bytes32("BOB");
    bytes32 constant CODE_CAROL = bytes32("CAROL");

    // Storage slots (from forge inspect DegenerusGame storage-layout)
    uint256 constant SLOT_LEVEL = 0; // level is at slot 0, offset 0, 3 bytes (uint24)
    uint256 constant SLOT_LEVEL_DGNRS_ALLOCATION = 51;
    uint256 constant SLOT_LEVEL_DGNRS_CLAIMED = 52;

    uint256 buyerNonce;

    function setUp() public {
        _deployProtocol();
        alice = makeAddr("alice");
        bob   = makeAddr("bob");
        carol = makeAddr("carol");

        vm.prank(alice);
        affiliate.createAffiliateCode(CODE_ALICE, 0);
        vm.prank(bob);
        affiliate.createAffiliateCode(CODE_BOB, 0);
        vm.prank(carol);
        affiliate.createAffiliateCode(CODE_CAROL, 0);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _claimDgnrs(address player) internal {
        vm.prank(player);
        game.claimAffiliateDgnrs(address(0));
    }

    /// @dev Purchase with a unique buyer using an affiliate code.
    function _buyOne(bytes32 code) internal {
        address buyer = address(uint160(0xB0000 + buyerNonce++));
        vm.deal(buyer, 5 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(
            buyer, 400, 1 ether, code, MintPaymentKind.DirectEth
        );
    }

    /// @dev Compute the storage slot for a mapping(uint24 => uint256) at baseSlot.
    function _mappingSlot(uint256 baseSlot, uint24 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(key), baseSlot));
    }

    /// @dev Set levelDgnrsAllocation[lvl] = value via vm.store.
    function _setAllocation(uint24 lvl, uint256 value) internal {
        vm.store(address(game), _mappingSlot(SLOT_LEVEL_DGNRS_ALLOCATION, lvl), bytes32(value));
    }

    /// @dev Read levelDgnrsClaimed[lvl] via vm.load.
    function _getClaimed(uint24 lvl) internal view returns (uint256) {
        return uint256(vm.load(address(game), _mappingSlot(SLOT_LEVEL_DGNRS_CLAIMED, lvl)));
    }

    /// @dev Set game.level = lvl in packed slot 0.
    ///      level is uint24 at offset 18 bytes (144 bits from LSB).
    function _setLevel(uint24 lvl) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFFFFFF) << 144;
        slot0 = (slot0 & ~mask) | (uint256(lvl) << 144);
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Build affiliate scores using N distinct buyers, then set up the
    ///      game state for claiming: advance level and set allocation.
    function _buildScoresAndSetupClaim(
        bytes32 code1, uint256 numBuyers1,
        bytes32 code2, uint256 numBuyers2
    ) internal returns (uint24 claimLevel) {
        // All purchases happen at level 0, scores route to level 1
        for (uint256 i = 0; i < numBuyers1; i++) _buyOne(code1);
        for (uint256 i = 0; i < numBuyers2; i++) _buyOne(code2);

        claimLevel = 1; // scores went to level+1 = 0+1 = 1

        // Simulate level transition: set level to 1
        _setLevel(claimLevel);

        // Set allocation (5% of a hypothetical 10M token affiliate pool)
        uint256 allocation = 500_000 ether; // 500k DGNRS
        _setAllocation(claimLevel, allocation);
    }

    // =========================================================================
    // Score Routing
    // =========================================================================

    /// @notice Scores route to level + 1 during purchase phase
    function test_scoresRouteToLevelPlusOne() public {
        assertEq(game.level(), 0);
        _buyOne(CODE_ALICE);

        assertEq(affiliate.affiliateScore(0, alice), 0, "No score at level 0");
        assertTrue(affiliate.affiliateScore(1, alice) > 0, "Score at level 1");
    }

    /// @notice totalAffiliateScore accumulates across multiple buyers
    function test_totalScoreAccumulates() public {
        for (uint256 i = 0; i < 5; i++) _buyOne(CODE_ALICE);
        for (uint256 i = 0; i < 3; i++) _buyOne(CODE_BOB);

        uint256 a = affiliate.affiliateScore(1, alice);
        uint256 b = affiliate.affiliateScore(1, bob);
        uint256 total = affiliate.totalAffiliateScore(1);

        assertTrue(a > 0 && b > 0, "Both have scores");
        // Total includes vault/default affiliate from any unaffiliated buys
        assertTrue(total >= a + b, "Total >= sum of known");
        assertEq(total, a + b, "Only two affiliates used - total should equal sum");
    }

    // =========================================================================
    // Claim Reverts
    // =========================================================================

    /// @notice Cannot claim at level 0
    function test_revertClaimAtLevel0() public {
        vm.expectRevert();
        _claimDgnrs(alice);
    }

    /// @notice Zero-score affiliate cannot claim
    function test_revertZeroScore() public {
        // Alice has score, Bob doesn't
        for (uint256 i = 0; i < 30; i++) _buyOne(CODE_ALICE);
        _setLevel(1);
        _setAllocation(1, 1_000_000 ether);

        vm.expectRevert();
        _claimDgnrs(bob);
    }

    /// @notice Score below AFFILIATE_DGNRS_MIN_SCORE (10 ETH) reverts
    function test_revertBelowMinScore() public {
        // 1 buyer → ~0.5 ETH score (per-sender commission cap)
        _buyOne(CODE_BOB);
        _setLevel(1);
        _setAllocation(1, 1_000_000 ether);

        uint256 bobScore = affiliate.affiliateScore(1, bob);
        assertTrue(bobScore < 10 ether, "Score below min");

        vm.expectRevert();
        _claimDgnrs(bob);
    }

    /// @notice Cannot double-claim same level
    function test_revertDoubleClaim() public {
        for (uint256 i = 0; i < 25; i++) _buyOne(CODE_ALICE);
        _setLevel(1);
        _setAllocation(1, 1_000_000 ether);

        _claimDgnrs(alice);

        vm.expectRevert();
        _claimDgnrs(alice);
    }

    /// @notice Revert when allocation is zero (no transition happened)
    function test_revertZeroAllocation() public {
        for (uint256 i = 0; i < 25; i++) _buyOne(CODE_ALICE);
        _setLevel(1);
        // Don't set allocation — stays 0

        vm.expectRevert();
        _claimDgnrs(alice);
    }

    // =========================================================================
    // Proportional Distribution
    // =========================================================================

    /// @notice Two affiliates get rewards proportional to their scores
    function test_proportionalDistribution() public {
        // Alice: 40 buyers (~20 ETH score), Bob: 25 buyers (~12.5 ETH score)
        uint24 lvl = _buildScoresAndSetupClaim(CODE_ALICE, 40, CODE_BOB, 25);

        uint256 aliceScore = affiliate.affiliateScore(lvl, alice);
        uint256 bobScore   = affiliate.affiliateScore(lvl, bob);

        assertTrue(aliceScore > 10 ether, "Alice above min");
        assertTrue(bobScore > 10 ether, "Bob above min");

        uint256 aliceBefore = dgnrs.balanceOf(alice);
        uint256 bobBefore   = dgnrs.balanceOf(bob);

        _claimDgnrs(alice);
        _claimDgnrs(bob);

        uint256 aliceReward = dgnrs.balanceOf(alice) - aliceBefore;
        uint256 bobReward   = dgnrs.balanceOf(bob) - bobBefore;

        assertTrue(aliceReward > 0 && bobReward > 0, "Both got rewards");

        // Reward ratio should match score ratio within 0.1%
        uint256 expectedRatio = (aliceScore * 1e18) / bobScore;
        uint256 actualRatio   = (aliceReward * 1e18) / bobReward;
        assertApproxEqRel(actualRatio, expectedRatio, 1e15, "Proportional distribution");
    }

    // =========================================================================
    // Order Independence
    // =========================================================================

    /// @notice Claim order doesn't affect reward amounts
    function test_orderIndependence() public {
        uint24 lvl = _buildScoresAndSetupClaim(CODE_ALICE, 30, CODE_BOB, 30);

        uint256 aliceScore = affiliate.affiliateScore(lvl, alice);
        uint256 bobScore   = affiliate.affiliateScore(lvl, bob);

        // Bob claims FIRST
        uint256 bobBefore = dgnrs.balanceOf(bob);
        _claimDgnrs(bob);
        uint256 bobReward = dgnrs.balanceOf(bob) - bobBefore;

        uint256 aliceBefore = dgnrs.balanceOf(alice);
        _claimDgnrs(alice);
        uint256 aliceReward = dgnrs.balanceOf(alice) - aliceBefore;

        assertTrue(aliceReward > 0 && bobReward > 0, "Both got rewards");

        // Reward ratio matches score ratio regardless of order
        uint256 expectedRatio = (aliceScore * 1e18) / bobScore;
        uint256 actualRatio   = (aliceReward * 1e18) / bobReward;
        assertApproxEqRel(actualRatio, expectedRatio, 1e15, "Order independent");
    }

    // =========================================================================
    // Pool Isolation
    // =========================================================================

    /// @notice Total claims match pool delta
    function test_totalClaimsMatchPoolDelta() public {
        uint24 lvl = _buildScoresAndSetupClaim(CODE_ALICE, 30, CODE_BOB, 25);

        uint256 poolBefore = dgnrs.poolBalance(DegenerusStonk.Pool.Affiliate);

        uint256 bal;
        uint256 totalClaimed;

        bal = dgnrs.balanceOf(alice);
        _claimDgnrs(alice);
        totalClaimed += dgnrs.balanceOf(alice) - bal;

        bal = dgnrs.balanceOf(bob);
        _claimDgnrs(bob);
        totalClaimed += dgnrs.balanceOf(bob) - bal;

        uint256 poolAfter = dgnrs.poolBalance(DegenerusStonk.Pool.Affiliate);
        assertEq(totalClaimed, poolBefore - poolAfter, "Claims match pool delta");
    }

    /// @notice Total claims never exceed allocation
    function test_totalClaimsLeAllocation() public {
        uint24 lvl = _buildScoresAndSetupClaim(CODE_ALICE, 30, CODE_BOB, 25);

        // Use a small allocation to test the cap behavior
        uint256 smallAllocation = 100 ether;
        _setAllocation(lvl, smallAllocation);

        uint256 bal;
        uint256 totalClaimed;

        bal = dgnrs.balanceOf(alice);
        _claimDgnrs(alice);
        totalClaimed += dgnrs.balanceOf(alice) - bal;

        bal = dgnrs.balanceOf(bob);
        _claimDgnrs(bob);
        totalClaimed += dgnrs.balanceOf(bob) - bal;

        assertTrue(totalClaimed <= smallAllocation, "Total claimed <= allocation");
        // With exact denominator, total should be close to allocation
        // (minus rounding dust from integer division)
        assertApproxEqAbs(totalClaimed, smallAllocation, 2, "Total claimed ~= allocation");
    }

    /// @notice levelDgnrsClaimed tracks cumulative claims correctly
    function test_claimedTrackingAccumulates() public {
        uint24 lvl = _buildScoresAndSetupClaim(CODE_ALICE, 30, CODE_BOB, 25);

        assertEq(_getClaimed(lvl), 0, "Nothing claimed initially");

        uint256 bal = dgnrs.balanceOf(alice);
        _claimDgnrs(alice);
        uint256 alicePaid = dgnrs.balanceOf(alice) - bal;

        assertEq(_getClaimed(lvl), alicePaid, "Claimed = alice's reward");

        bal = dgnrs.balanceOf(bob);
        _claimDgnrs(bob);
        uint256 bobPaid = dgnrs.balanceOf(bob) - bal;

        assertEq(_getClaimed(lvl), alicePaid + bobPaid, "Claimed = alice + bob");
    }

    // =========================================================================
    // Claim Window (1 level only)
    // =========================================================================

    /// @notice Claims use currLevel — moving to next level orphans old allocation
    function test_claimWindowMovesWithLevel() public {
        // Build scores at level 1, set up claim
        for (uint256 i = 0; i < 30; i++) _buyOne(CODE_ALICE);
        _setLevel(1);
        _setAllocation(1, 500_000 ether);

        // Alice can claim at level 1
        uint256 before = dgnrs.balanceOf(alice);
        _claimDgnrs(alice);
        assertTrue(dgnrs.balanceOf(alice) - before > 0, "Claimed at level 1");

        // Move to level 2 — Alice's level-1 scores are no longer accessible
        _setLevel(2);
        _setAllocation(2, 500_000 ether);

        // Bob had no score at level 2 → reverts
        vm.expectRevert();
        _claimDgnrs(bob);

        // Alice also has no score at level 2 (her purchases were during level 0 → score at 1)
        vm.expectRevert();
        _claimDgnrs(alice);
    }

    // =========================================================================
    // Three Affiliates
    // =========================================================================

    /// @notice Three affiliates with different volumes get correct proportions
    function test_threeAffiliatesProportional() public {
        // Alice: 40, Bob: 30, Carol: 25 buyers
        for (uint256 i = 0; i < 40; i++) _buyOne(CODE_ALICE);
        for (uint256 i = 0; i < 30; i++) _buyOne(CODE_BOB);
        for (uint256 i = 0; i < 25; i++) _buyOne(CODE_CAROL);

        uint24 lvl = 1;
        _setLevel(lvl);
        _setAllocation(lvl, 1_000_000 ether);

        uint256 aScore = affiliate.affiliateScore(lvl, alice);
        uint256 bScore = affiliate.affiliateScore(lvl, bob);
        uint256 cScore = affiliate.affiliateScore(lvl, carol);
        uint256 total  = affiliate.totalAffiliateScore(lvl);

        assertEq(total, aScore + bScore + cScore, "Total = sum (no other affiliates)");

        uint256 aBefore = dgnrs.balanceOf(alice);
        uint256 bBefore = dgnrs.balanceOf(bob);
        uint256 cBefore = dgnrs.balanceOf(carol);

        _claimDgnrs(alice);
        _claimDgnrs(bob);
        _claimDgnrs(carol);

        uint256 aReward = dgnrs.balanceOf(alice) - aBefore;
        uint256 bReward = dgnrs.balanceOf(bob) - bBefore;
        uint256 cReward = dgnrs.balanceOf(carol) - cBefore;

        // Alice/Bob ratio
        assertApproxEqRel(
            (aReward * 1e18) / bReward,
            (aScore * 1e18) / bScore,
            1e15, "Alice/Bob proportional"
        );
        // Alice/Carol ratio
        assertApproxEqRel(
            (aReward * 1e18) / cReward,
            (aScore * 1e18) / cScore,
            1e15, "Alice/Carol proportional"
        );
        // Bob/Carol ratio
        assertApproxEqRel(
            (bReward * 1e18) / cReward,
            (bScore * 1e18) / cScore,
            1e15, "Bob/Carol proportional"
        );
    }
}
