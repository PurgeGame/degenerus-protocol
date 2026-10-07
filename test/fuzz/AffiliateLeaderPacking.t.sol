// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title AffiliateLeaderPacking -- the level total and the leader's score share one word
/// @notice Drives payAffiliate and payAffiliateCombined as the Game, then checks the public
///         views against a reference model, the tie rule (an equal score keeps the earlier
///         leader), the packed layout, and that an earning which does not take the lead never
///         reads or writes the leader address slot.
contract AffiliateLeaderPacking is DeployProtocol {
    // forge inspect DegenerusAffiliate storage-layout
    uint256 constant SLOT_TOP = 3; // affiliateTopByLevel: mapping(uint24 => address)
    uint256 constant SLOT_TOTAL = 4; // _totalAffiliateScore: total [0:160) | leader score [160:256)
    uint24 constant LVL = 5;

    address[4] affs;
    bytes32[4] codes;
    uint256 buyerNonce;

    function setUp() public {
        _deployProtocol();
        for (uint256 i; i < 4; ++i) {
            affs[i] = makeAddr(string.concat("aff", vm.toString(i)));
            codes[i] = bytes32(bytes.concat("AFF", bytes1(uint8(0x41 + i))));
            vm.prank(affs[i]);
            affiliate.createAffiliateCode(codes[i], 0);
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

    function _assertViews(address leader, uint256 leaderScore, uint256 total) internal view {
        (address top, uint96 topScore) = affiliate.affiliateTop(LVL);
        assertEq(top, leader, "leader");
        assertEq(topScore, leaderScore, "leader score");
        assertEq(affiliate.totalAffiliateScore(LVL), total, "total");
    }

    /// @dev Reference model: total = sum of every recorded earning; leader = first affiliate
    ///      to reach a strictly higher score than the standing leader.
    function testFuzz_ViewsMatchReferenceModel(uint256 seed) public {
        uint256 total;
        address leader;
        uint256 leaderScore;
        for (uint256 i; i < 24; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            uint256 k = r % 4;
            uint256 before = affiliate.affiliateScore(LVL, affs[k]);
            if ((r >> 72) % 3 == 0) {
                _earnCombined(k, (1 + (r >> 8) % 4000) * 1, ((r >> 40) % 3000) * 1);
            } else {
                _earn(k, (1 + (r >> 8) % 5000) * 1, (r >> 64) & 1 == 0);
            }
            uint256 afterScore = affiliate.affiliateScore(LVL, affs[k]);
            total += afterScore - before;
            if (afterScore > leaderScore) {
                leader = affs[k];
                leaderScore = afterScore;
            }
            _assertViews(leader, leaderScore, total);
        }
    }

    function test_EqualScoreKeepsEarlierLeader() public {
        _earn(0, 1000, true);
        _earn(1, 1000, true);
        uint256 s = affiliate.affiliateScore(LVL, affs[0]);
        assertEq(affiliate.affiliateScore(LVL, affs[1]), s, "equal scores");
        _assertViews(affs[0], s, 2 * s);

        _earn(1, 5, true); // 20% of five whole FLIP adds one point and breaks the tie
        uint256 s1 = affiliate.affiliateScore(LVL, affs[1]);
        _assertViews(affs[1], s1, s + s1);
    }

    function test_PackedWordLayout() public {
        _earn(0, 3000, true);
        _earn(1, 1000, true);
        uint256 s0 = affiliate.affiliateScore(LVL, affs[0]);
        uint256 s1 = affiliate.affiliateScore(LVL, affs[1]);
        uint256 word = uint256(vm.load(address(affiliate), _slot(SLOT_TOTAL)));
        assertEq(word & type(uint160).max, s0 + s1, "low half = total");
        assertEq(word >> 160, s0, "high half = leader score");
        assertEq(address(uint160(uint256(vm.load(address(affiliate), _slot(SLOT_TOP))))), affs[0], "leader slot");
    }

    function _touches(bytes32[] memory slots, bytes32 target) internal pure returns (bool) {
        for (uint256 i; i < slots.length; ++i) {
            if (slots[i] == target) return true;
        }
        return false;
    }

    function test_NonLeadingEarningSkipsLeaderSlot() public {
        _earn(0, 5000, true);
        bytes32 top = _slot(SLOT_TOP);

        vm.record();
        _earn(1, 100, true);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(affiliate));
        assertFalse(_touches(reads, top), "non-leading read the leader slot");
        assertFalse(_touches(writes, top), "non-leading wrote the leader slot");

        vm.record();
        _earn(1, 50_000, true);
        (, writes) = vm.accesses(address(affiliate));
        assertTrue(_touches(writes, top), "a new leader writes the leader slot");
        (address leader,) = affiliate.affiliateTop(LVL);
        assertEq(leader, affs[1]);
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
