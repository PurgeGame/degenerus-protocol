// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DeityBoonViewer} from "../../contracts/DeityBoonViewer.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract GiftDaySeeder is WalletSeed {
    function seed(uint24 day, uint256 word, address deity) external {
        _recordDailyRng(day, word);
        _seedWallet(deity);
        mintPacked_[_walletIdOf(deity)] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
    }
}

/// @title DeityGiftExpiredLane
/// @notice A manual deity gift applies without the box-roll expiry sweep. An expired lane in the
///         rolled family never blocks the gift (it would otherwise spend the deity's slot and the
///         pair's lifetime count for nothing); a live stronger lane still does.
contract DeityGiftExpiredLane is DeployProtocol {
    address private constant DEITY = address(0xDE17);
    address private constant RECIPIENT = address(0xB001);
    uint24 private constant TODAY = 41;
    uint24 private constant STALE = TODAY - 10;

    // Boon packing (DegenerusGameStorage BP_*): slot0 coinflip/lootbox/purchase, slot1 lazy pass.
    uint256 private constant CF_DAY = 0;
    uint256 private constant CF_DEITY = 24;
    uint256 private constant CF_TIER = 48;
    uint256 private constant LB_DAY = 56;
    uint256 private constant LB_DEITY = 80;
    uint256 private constant LB_TIER = 104;
    uint256 private constant PU_DAY = 112;
    uint256 private constant PU_DEITY = 136;
    uint256 private constant PU_TIER = 160;
    uint256 private constant LZ_DAY = 128;
    uint256 private constant LZ_DEITY = 152;
    uint256 private constant LZ_TIER = 176;

    DeityBoonViewer private viewer;
    uint32 private deityId;
    uint32 private recipientId;
    uint8 private giftSlot;
    uint8 private giftType;

    function setUp() public {
        _deployProtocol();
        viewer = new DeityBoonViewer();
        _giveWalletId(RECIPIENT);
        vm.warp((uint256(TODAY - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        _setRequestedFixtureDay(TODAY);
        // Find a menu word whose slot rolls one of the four families the fix covers.
        for (uint256 word = 0x1000; word < 0x1100 && giftType == 0; ++word) {
            _seed(TODAY - 1, word);
            (uint8[3] memory menu,,) = viewer.deityBoonSlots(address(game), DEITY);
            for (uint8 i; i < 3; ++i) {
                if (_family(menu[i]) != 0) {
                    giftSlot = i;
                    giftType = menu[i];
                    break;
                }
            }
        }
        require(giftType != 0, "no covered family on the menu");
        _seed(TODAY, 0xBEEF);
        deityId = game.walletIdOf_g3120(DEITY);
        recipientId = game.walletIdOf_g3120(RECIPIENT);
    }

    function _seed(uint24 day, uint256 word) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(GiftDaySeeder).runtimeCode);
        GiftDaySeeder(address(game)).seed(day, word, DEITY);
        vm.etch(address(game), code);
    }

    /// @dev 1 coinflip, 2 lootbox boost, 3 purchase boost, 4 lazy-pass discount, 0 other.
    function _family(uint8 boonType) private pure returns (uint8) {
        if (boonType >= 1 && boonType <= 3) return 1;
        if (boonType == 5 || boonType == 6 || boonType == 22) return 2;
        if (boonType >= 7 && boonType <= 9) return 3;
        if (boonType >= 29 && boonType <= 31) return 4;
        return 0;
    }

    function _boonSlot() private view returns (bytes32) {
        return keccak256(abi.encode(uint256(recipientId), GameSlots.BOON_PACKED));
    }

    function _setBoon(uint256 s0, uint256 s1) private {
        bytes32 slot = _boonSlot();
        vm.store(address(game), slot, bytes32(s0));
        vm.store(address(game), bytes32(uint256(slot) + 1), bytes32(s1));
    }

    /// @dev Every covered family holds tier 3, rolled on `stampDay` (no deity stamp).
    function _holdTier3(uint24 stampDay) private {
        uint256 s0 = (uint256(stampDay) << CF_DAY) | (uint256(3) << CF_TIER)
            | (uint256(stampDay) << LB_DAY) | (uint256(3) << LB_TIER)
            | (uint256(stampDay) << PU_DAY) | (uint256(3) << PU_TIER);
        uint256 s1 = (uint256(stampDay) << LZ_DAY) | (uint256(3) << LZ_TIER);
        _setBoon(s0, s1);
    }

    /// @dev The gift family's (day, deity day, tier) after the gift.
    function _lane() private view returns (uint24 day, uint24 deityDay, uint8 tier) {
        bytes32 slot = _boonSlot();
        uint256 s0 = uint256(vm.load(address(game), slot));
        uint256 s1 = uint256(vm.load(address(game), bytes32(uint256(slot) + 1)));
        uint8 fam = _family(giftType);
        (uint256 w, uint256 d, uint256 dd, uint256 t) = fam == 1 ? (s0, CF_DAY, CF_DEITY, CF_TIER)
            : fam == 2 ? (s0, LB_DAY, LB_DEITY, LB_TIER)
            : fam == 3 ? (s0, PU_DAY, PU_DEITY, PU_TIER)
            : (s1, LZ_DAY, LZ_DEITY, LZ_TIER);
        day = uint24(w >> d);
        deityDay = uint24(w >> dd);
        tier = uint8(w >> t);
    }

    function _gift() private {
        vm.prank(DEITY);
        game.giveBoon(deityId, recipientId, giftSlot);
    }

    function test_expiredLaneDoesNotBlockGift() public {
        _holdTier3(STALE);
        _gift();
        (uint24 day, uint24 deityDay, uint8 tier) = _lane();
        assertEq(day, TODAY, "gift stamps today");
        assertEq(deityDay, TODAY, "gift is deity-stamped");
        assertGt(tier, 0);
        assertLe(tier, 3);
    }

    function test_liveStrongerLaneStillBlocksGift() public {
        _holdTier3(TODAY);
        _gift();
        (uint24 day, uint24 deityDay, uint8 tier) = _lane();
        assertEq(day, TODAY, "held stamp kept");
        assertEq(deityDay, 0, "held lane stays rolled, not deity-stamped");
        assertEq(tier, 3, "stronger live lane kept");
    }
}
