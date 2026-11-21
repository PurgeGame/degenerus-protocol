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
        _pick(0);
    }

    /// @dev Seed a menu whose slot rolls family `fam` (0 = any covered family), then reseed the gift day.
    function _pick(uint8 fam) private {
        giftType = 0;
        for (uint256 word = 0x1000; word < 0x1800 && giftType == 0; ++word) {
            _seed(TODAY - 1, word);
            (uint8[3] memory menu,,) = viewer.deityBoonSlots(address(game), DEITY);
            for (uint8 i; i < 3; ++i) {
                uint8 f = _family(menu[i]);
                if (f != 0 && (fam == 0 || f == fam)) {
                    giftSlot = i;
                    giftType = menu[i];
                    break;
                }
            }
        }
        require(giftType != 0, "family not on any menu");
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

    /// @dev Days a held boon of the family stays live after its stamp day.
    function _expiry(uint8 fam) private pure returns (uint24) {
        return fam <= 2 ? 2 : 4;
    }

    /// @dev The family's lane holds tier 3 stamped `stamp`; every other family's lane carries the opposite
    ///      liveness (stale when the family's is live, today when it is expired), so a read of another
    ///      family's stamp gives the wrong answer.
    function _holdLane(uint8 fam, uint24 stamp, bool live) private {
        uint256 other = live ? STALE : TODAY;
        uint256 s0 = ((fam == 1 ? uint256(stamp) : other) << CF_DAY)
            | ((fam == 2 ? uint256(stamp) : other) << LB_DAY)
            | ((fam == 3 ? uint256(stamp) : other) << PU_DAY);
        if (fam == 1) s0 |= uint256(3) << CF_TIER;
        if (fam == 2) s0 |= uint256(3) << LB_TIER;
        if (fam == 3) s0 |= uint256(3) << PU_TIER;
        uint256 s1 = (fam == 4 ? uint256(stamp) : other) << LZ_DAY;
        if (fam == 4) s1 |= uint256(3) << LZ_TIER;
        _setBoon(s0, s1);
    }

    /// @dev A held boon on its last valid day is live: the gift is blocked and the lane is untouched.
    function _assertLiveOnLastValidDay(uint8 fam) private {
        _pick(fam);
        uint24 stamp = TODAY - _expiry(fam);
        _holdLane(fam, stamp, true);
        _gift();
        (uint24 day, uint24 deityDay, uint8 tier) = _lane();
        assertEq(day, stamp, "held stamp kept");
        assertEq(deityDay, 0, "held lane not deity-stamped");
        assertEq(tier, 3, "live lane kept");
    }

    /// @dev A held boon one day past its last valid day is expired: the gift applies over it.
    function _assertExpiredOneDayLater(uint8 fam) private {
        _pick(fam);
        _holdLane(fam, TODAY - _expiry(fam) - 1, false);
        _gift();
        (uint24 day, uint24 deityDay, uint8 tier) = _lane();
        assertEq(day, TODAY, "gift stamps today");
        assertEq(deityDay, TODAY, "gift is deity-stamped");
        assertGt(tier, 0);
        assertLe(tier, 3);
    }

    function test_coinflipLaneLiveOnLastValidDay() public { _assertLiveOnLastValidDay(1); }
    function test_coinflipLaneExpiredOneDayLater() public { _assertExpiredOneDayLater(1); }
    function test_lootboxLaneLiveOnLastValidDay() public { _assertLiveOnLastValidDay(2); }
    function test_lootboxLaneExpiredOneDayLater() public { _assertExpiredOneDayLater(2); }
    function test_purchaseLaneLiveOnLastValidDay() public { _assertLiveOnLastValidDay(3); }
    function test_purchaseLaneExpiredOneDayLater() public { _assertExpiredOneDayLater(3); }
    function test_lazyPassLaneLiveOnLastValidDay() public { _assertLiveOnLastValidDay(4); }
    function test_lazyPassLaneExpiredOneDayLater() public { _assertExpiredOneDayLater(4); }
}
