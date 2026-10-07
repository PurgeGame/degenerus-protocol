// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title AffiliateLeaderPacking -- the level total and the leader's score share one word
/// @notice Drives payAffiliate and payAffiliateCombined as the Game, then checks the public
///         views against a reference model, the tie rule (an equal score keeps the earlier
///         leader), the packed layout (total, leader score and leader ID in one word), the
///         saturating total, and that an earning which does not take the lead leaves the
///         leader fields untouched.
contract AffiliateLeaderPacking is DeployProtocol {
    // forge inspect DegenerusAffiliate storage-layout
    uint256 constant SLOT_TOTAL = 3; // _levelScore: total [0:128) | leader score [128:224) | leader ID [224:256)
    uint24 constant LVL = 5;

    address[4] affs;
    uint32[4] ids;
    bytes32[4] codes;
    uint256 buyerNonce;

    function setUp() public {
        _deployProtocol();
        for (uint256 i; i < 4; ++i) {
            affs[i] = makeAddr(string.concat("aff", vm.toString(i)));
            codes[i] = bytes32(bytes.concat("AFF", bytes1(uint8(0x41 + i))));
            vm.prank(affs[i]);
            affiliate.createAffiliateCode(codes[i], 0);
            ids[i] = game.walletIdOf(affs[i]);
            assertGt(ids[i], 0);
        }
    }

    function _buyer() internal returns (address) {
        return address(uint160(0xB0000 + buyerNonce++));
    }

    function _earn(uint256 k, uint256 amount, bool fresh) internal {
        vm.prank(address(game));
        address buyer = _buyer();
        affiliate.payAffiliate(amount, codes[k], buyer, uint32(uint160(buyer)), LVL, fresh, 0);
    }

    function _earnCombined(uint256 k, uint256 tktFresh, uint256 lbFresh) internal {
        vm.prank(address(game));
        address buyer = _buyer();
        affiliate.payAffiliateCombined(codes[k], buyer, uint32(uint160(buyer)), LVL, tktFresh, 0, lbFresh, 0, 0);
    }

    function _slot(uint256 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(LVL), base));
    }

    function _assertViews(uint32 leader, uint256 leaderScore, uint256 total) internal view {
        (uint32 top, uint96 topScore) = affiliate.affiliateTop(LVL);
        assertEq(top, leader, "leader");
        assertEq(topScore, leaderScore, "leader score");
        assertEq(affiliate.totalAffiliateScore(LVL), total, "total");
    }

    /// @dev Reference model: total = sum of every recorded earning; leader = first affiliate
    ///      to reach a strictly higher score than the standing leader.
    function testFuzz_ViewsMatchReferenceModel(uint256 seed) public {
        uint256 total;
        uint32 leader;
        uint256 leaderScore;
        for (uint256 i; i < 24; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            uint256 k = r % 4;
            uint256 before = affiliate.affiliateScore(LVL, ids[k]);
            if ((r >> 72) % 3 == 0) {
                _earnCombined(k, (1 + (r >> 8) % 4000) * 1, ((r >> 40) % 3000) * 1);
            } else {
                _earn(k, (1 + (r >> 8) % 5000) * 1, (r >> 64) & 1 == 0);
            }
            uint256 afterScore = affiliate.affiliateScore(LVL, ids[k]);
            total += afterScore - before;
            if (afterScore > leaderScore) {
                leader = ids[k];
                leaderScore = afterScore;
            }
            _assertViews(leader, leaderScore, total);
        }
    }

    function test_EqualScoreKeepsEarlierLeader() public {
        _earn(0, 1000, true);
        _earn(1, 1000, true);
        uint256 s = affiliate.affiliateScore(LVL, ids[0]);
        assertEq(affiliate.affiliateScore(LVL, ids[1]), s, "equal scores");
        _assertViews(ids[0], s, 2 * s);

        _earn(1, 5, true); // 20% of five whole FLIP adds one point and breaks the tie
        uint256 s1 = affiliate.affiliateScore(LVL, ids[1]);
        _assertViews(ids[1], s1, s + s1);
    }

    function test_EmptyLevelHasNoLeader() public view {
        _assertViews(0, 0, 0);
        assertEq(uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL))), 0);
    }

    function test_PackedWordLayout() public {
        _earn(0, 3000, true);
        _earn(1, 1000, true);
        uint256 s0 = affiliate.affiliateScore(LVL, ids[0]);
        uint256 s1 = affiliate.affiliateScore(LVL, ids[1]);
        uint256 word = uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL)));
        assertEq(word & type(uint128).max, s0 + s1, "total");
        assertEq((word >> 128) & type(uint96).max, s0, "leader score");
        assertEq(word >> 224, ids[0], "leader ID");
    }

    function test_TotalSaturates() public {
        _earn(0, 3000, true);
        uint256 word = uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL)));
        uint256 saturated = (word & ~uint256(type(uint128).max)) | (uint256(type(uint128).max) - 1);
        vm.store(address(affiliate), _slot(SLOT_TOTAL), bytes32(saturated));
        _earn(1, 1000, true);
        uint256 after_ = uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL)));
        assertEq(after_ & type(uint128).max, type(uint128).max, "total saturates");
        assertEq(after_ >> 128, saturated >> 128, "leader fields untouched");
        assertEq(affiliate.totalAffiliateScore(LVL), type(uint128).max);
    }

    function test_NonLeadingEarningLeavesLeaderFields() public {
        _earn(0, 5000, true);
        uint256 leaderBits = uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL))) >> 128;

        _earn(1, 100, true);
        assertEq(uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL))) >> 128, leaderBits, "leader fields moved");
        (uint32 leader,) = affiliate.affiliateTop(LVL);
        assertEq(leader, ids[0]);

        _earn(1, 50_000, true);
        assertTrue(uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL))) >> 128 != leaderBits, "a new leader rewrites them");
        (leader,) = affiliate.affiliateTop(LVL);
        assertEq(leader, ids[1]);
    }

    /// @dev Cold gas of one ordinary earning that does not take the lead (A/B evidence).
    function test_GasNonLeadingEarning() public {
        _earn(0, 5000, true);
        _earn(1, 100, true);
        address buyer = _buyer();
        vm.cool(address(affiliate));
        vm.cool(address(coinflip));
        vm.prank(address(game));
        uint256 g = gasleft();
        affiliate.payAffiliate(100, codes[1], buyer, uint32(uint160(buyer)), LVL, true, 0);
        g -= gasleft();
        emit log_named_uint("payAffiliate non-leading cold gas", g);
    }
}
