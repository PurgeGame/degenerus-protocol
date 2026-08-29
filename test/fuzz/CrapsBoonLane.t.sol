// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DeityBoonViewer} from "../../contracts/DeityBoonViewer.sol";

contract CrapsBoonModuleHarness is DegenerusGameBoonModule {
    function tree(uint256 roll) external pure returns (uint8) {
        return _boonFromRoll(roll);
    }

    function writeSlot1(address player, uint256 value) external {
        boonPacked[player].slot1 = value;
    }

    function writeSlot0(address player, uint256 value) external {
        boonPacked[player].slot0 = value;
    }

    function slot1Of(address player) external view returns (uint256) {
        return boonPacked[player].slot1;
    }

    function slot0Of(address player) external view returns (uint256) {
        return boonPacked[player].slot0;
    }

    function today() external view returns (uint24) {
        return _simulatedDayIndex();
    }
}

contract CrapsBoonViewerHarness is DeityBoonViewer {
    function tree(uint256 roll) external pure returns (uint8) {
        return _boonFromRoll(roll);
    }
}

/// @title CrapsBoonLane -- the craps stake boon's table position and its slot1 low lane
/// @notice Four things this owns, none of which another suite covers:
///
///         1. TREE PARITY. The module walks a balanced comparison tree and the viewer walks a
///            cumulative cursor. They are independent transcriptions of one table, and a deity's
///            published menu must be the menu that gets issued, so they are compared exhaustively
///            rather than sampled.
///         2. DEITY BAND COMPOSITION. The deity roll skips the decimator and deity-pass bands
///            arithmetically. Appending craps at the TAIL must leave that skip intact -- and the
///            craps types must be reachable through it, since a deity gift of a craps boon is a
///            live award.
///         3. LANE DECODE. The lane shares its 24-bit encoding with a degenerette lane but decodes
/// 5/10/15% off the coinflip table, not tier x 400. A slip here silently pays the wrong
///            bonus, which no weight-table test would catch.
///         4. LANE DISJOINTNESS. One selector serves two lanes and the caller names which. COINFLIP
///            must never reach the craps lane and COIN must never reach the coinflip lane.
contract CrapsBoonLane is Test {
    CrapsBoonModuleHarness private module_;
    CrapsBoonViewerHarness private viewer;

    uint16 private constant W_TOTAL = 2856;
    uint16 private constant W_DECIMATOR_ALL = 50;
    uint16 private constant W_DEITY_PASS_ALL = 40;
    uint16 private constant W_PRE_DECIMATOR = 982;
    uint16 private constant W_PRE_DEITY_PASS = 1072;

    uint8 private constant BOON_CRAPS_5 = 41;
    uint8 private constant BOON_CRAPS_15 = 43;

    /// @dev Lane encoding shared with the degenerette lanes: [day:21 | isDeity:1 | tier:2].
    uint256 private constant LANE_MASK = 0xFFFFFF;
    uint256 private constant LANE_DAY_SHIFT = 3;
    uint256 private constant LANE_DEITY_BIT = 0x4;
    uint24 private constant EXPIRY_DAYS = 2;

    address private constant PLAYER = address(0xC7A95);

    function setUp() public {
        module_ = new CrapsBoonModuleHarness();
        viewer = new CrapsBoonViewerHarness();
    }

    function _lane(uint8 tier, bool isDeity, uint24 stampDay) private pure returns (uint256) {
        return (uint256(stampDay & 0x1FFFFF) << LANE_DAY_SHIFT) | (isDeity ? LANE_DEITY_BIT : 0) | uint256(tier);
    }

    // ---------------------------------------------------------------------
    // 1. Tree parity
    // ---------------------------------------------------------------------

    function testModuleAndViewerTreesAgreeOnEveryReachableRoll() public view {
        for (uint256 roll; roll < W_TOTAL; ++roll) {
            assertEq(module_.tree(roll), viewer.tree(roll), "module/viewer tree drift");
        }
    }

    function testCrapsBandOccupiesTheTailInBothTrees() public view {
        assertEq(module_.tree(2607), 40, "tail boundary moved");
        assertEq(module_.tree(2608), 41, "craps band does not open at 2608");
        assertEq(module_.tree(2807), 41, "craps 5% band end");
        assertEq(module_.tree(2808), 42, "craps 10% band start");
        assertEq(module_.tree(2847), 42, "craps 10% band end");
        assertEq(module_.tree(2848), 43, "craps 15% band start");
        assertEq(module_.tree(W_TOTAL - 1), 43, "table does not end on craps 15%");
    }

    // ---------------------------------------------------------------------
    // 2. Deity band composition
    // ---------------------------------------------------------------------

    function testDeityCompositionSkipsLootboxOnlyBandsAndReachesCraps() public view {
        uint256 reduced = W_TOTAL - W_DECIMATOR_ALL - W_DEITY_PASS_ALL;
        bool sawCraps;
        for (uint256 r; r < reduced; ++r) {
            uint256 roll = r;
            if (roll >= W_PRE_DECIMATOR) roll += W_DECIMATOR_ALL;
            if (roll >= W_PRE_DEITY_PASS) roll += W_DEITY_PASS_ALL;
            uint8 t = module_.tree(roll);
            assertTrue(t < 13 || t > 15, "deity roll reached a decimator tier");
            assertTrue(t < 25 || t > 27, "deity roll reached a deity-pass tier");
            if (t >= BOON_CRAPS_5 && t <= BOON_CRAPS_15) sawCraps = true;
        }
        assertTrue(sawCraps, "craps unreachable as a deity gift");
    }

    // ---------------------------------------------------------------------
    // 3. Lane decode
    // ---------------------------------------------------------------------

    function testConsumeDecodesCoinflipTiersAndClearsTheLane() public {
        uint24 d = module_.today();
        uint16[4] memory expected = [uint16(0), 500, 1000, 2500];
        for (uint8 tier = 1; tier <= 3; ++tier) {
            module_.writeSlot1(PLAYER, _lane(tier, false, d));
            vm.prank(ContractAddresses.COIN);
            uint16 bps = module_.consumeCoinflipBoon(PLAYER);
            assertEq(bps, expected[tier], "craps tier decoded off the wrong table");
            assertEq(module_.slot1Of(PLAYER) & LANE_MASK, 0, "lane not cleared on consume");
        }
    }

    function testConsumePreservesEveryOtherSlot1Bit() public {
        uint24 d = module_.today();
        uint256 others = ~LANE_MASK;
        module_.writeSlot1(PLAYER, others | _lane(3, false, d));
        vm.prank(ContractAddresses.COIN);
        module_.consumeCoinflipBoon(PLAYER);
        assertEq(module_.slot1Of(PLAYER), others, "consume disturbed a neighbouring lane");
    }

    function testLootboxLaneLivesTwoDaysPastItsStampThenPaysNothing() public {
        uint24 d = module_.today();
        module_.writeSlot1(PLAYER, _lane(3, false, d));
        vm.warp(block.timestamp + uint256(EXPIRY_DAYS) * 1 days);
        vm.prank(ContractAddresses.COIN);
        assertEq(module_.consumeCoinflipBoon(PLAYER), 2500, "lane died inside its window");

        module_.writeSlot1(PLAYER, _lane(3, false, d));
        vm.warp(block.timestamp + 1 days);
        vm.prank(ContractAddresses.COIN);
        assertEq(module_.consumeCoinflipBoon(PLAYER), 0, "expired lane still paid");
        assertEq(module_.slot1Of(PLAYER) & LANE_MASK, 0, "expired lane not cleared");
    }

    function testDeityLaneDiesAtMidnightOfItsOwnDay() public {
        uint24 d = module_.today();
        module_.writeSlot1(PLAYER, _lane(2, true, d));
        vm.prank(ContractAddresses.COIN);
        assertEq(module_.consumeCoinflipBoon(PLAYER), 1000, "deity lane dead on its award day");

        module_.writeSlot1(PLAYER, _lane(2, true, d));
        vm.warp(block.timestamp + 1 days);
        vm.prank(ContractAddresses.COIN);
        assertEq(module_.consumeCoinflipBoon(PLAYER), 0, "deity lane outlived its day");
    }

    // ---------------------------------------------------------------------
    // 4. Lane disjointness -- one selector, two lanes, named by the caller
    // ---------------------------------------------------------------------

    function testCoinflipCallerCannotReachTheCrapsLane() public {
        uint24 d = module_.today();
        uint256 lane = _lane(3, false, d);
        module_.writeSlot1(PLAYER, lane);
        // No coinflip boon held: slot0 is empty, so COINFLIP must come away with nothing and
        // must not have spent the craps lane sitting in slot1.
        vm.prank(ContractAddresses.COINFLIP);
        assertEq(module_.consumeCoinflipBoon(PLAYER), 0, "coinflip caller paid off the craps lane");
        assertEq(module_.slot1Of(PLAYER), lane, "coinflip caller spent the craps lane");
    }

    function testCrapsCallerCannotReachTheCoinflipLane() public {
        uint24 d = module_.today();
        // A live tier-3 coinflip boon in slot0: tier at bit 48, stamp day at bit 0.
        uint256 s0 = (uint256(3) << 48) | uint256(d);
        module_.writeSlot0(PLAYER, s0);
        vm.prank(ContractAddresses.COIN);
        assertEq(module_.consumeCoinflipBoon(PLAYER), 0, "craps caller paid off the coinflip lane");
        assertEq(module_.slot0Of(PLAYER), s0, "craps caller spent the coinflip lane");
    }
}
