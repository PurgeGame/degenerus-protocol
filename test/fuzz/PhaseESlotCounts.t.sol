// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameSlots, CrapsSlots} from "../helpers/GameSlots.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";

/// @title PhaseESlotCounts -- plan section 6 slot-count asserts for the Phase E records
/// @notice Each record is written through its production door on the deployed protocol, then read
///         raw at its golden root (scripts/layout/golden/<Contract>.json): the fields decode at
///         their documented bit positions and the slot after the record stays zero.
///         - `PlayerCoinflipState` is two slots; the cached wallet ID sits in slot 0 at byte
///           offset 23 (bits 184..215), the auto-rebuy stop in slot 1.
///         - `AffiliateCodeInfo` is one slot: ownerId [0:32) kickback [32:40) upline1 [40:72)
///           upline2 [72:104) flags [104:112).
///         - A WWXRP incinerator entry is one slot: `cum | id << 192`.
///         - The Craps ID word `_passCreditsById[id]` is one slot: passes [0:64), board [64:84),
///           INITIALIZED [84]; its root is read from the compiled layout through CrapsViews.
contract PhaseESlotCountsTest is DeployProtocol {
    uint256 internal constant COINFLIP_PLAYER_STATE = 2;
    uint256 internal constant AFFILIATE_CODE = 0;
    uint256 internal constant WWXRP_INCIN_ENTRY = 7;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
    }

    /// @dev Seal the next day through the crank, so no Coinflip day is left unresolved.
    function _driveDay() internal {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("slots", i))) | 1);
            }
            try game.mineFlip() {} catch (bytes memory reason) {
                if (bytes4(reason) == bytes4(keccak256("NoWork()"))) return;
            }
        }
    }

    function _load(address target, bytes32 slot) internal view returns (uint256) {
        return uint256(vm.load(target, slot));
    }

    function _next(bytes32 slot) internal pure returns (bytes32) {
        return bytes32(uint256(slot) + 1);
    }

    function test_playerCoinflipStateIsTwoSlotsWithIdAtByte23() public {
        _driveDay();
        address p = makeAddr("coinflip-slots");
        vm.prank(address(game));
        coin.mintForGame(p, 1_000_000);
        assertEq(game.walletIdOf(p), 0, "fresh depositor");

        vm.prank(p);
        coinflip.depositCoinflip(p, 1_000);
        uint32 id = game.walletIdOf(p);
        assertGt(id, 3, "the deposit registered the depositor");

        bytes32 base = keccak256(abi.encode(p, COINFLIP_PLAYER_STATE));
        uint256 a = _load(address(coinflip), base);
        assertEq(uint32(a >> 184), id, "slot 0 bits 184..215 hold the wallet ID");
        assertEq(a >> 216, 0, "slot 0 above the ID is empty");
        assertEq(_load(address(coinflip), bytes32(uint256(base) + 2)), 0, "no third slot");

        vm.prank(p);
        coinflip.setCoinflipAutoRebuy(p, true, 777_000);
        a = _load(address(coinflip), base);
        uint256 b = _load(address(coinflip), _next(base));
        assertEq(uint32(a >> 184), id, "the ID survives a settings write");
        assertEq((a >> 176) & 0xFF, 1, "autoRebuyEnabled at byte 22");
        assertEq(uint128(b), 777_000, "slot 1 low half is the auto-rebuy stop");
        assertEq(_load(address(coinflip), bytes32(uint256(base) + 2)), 0, "still no third slot");
    }

    function test_affiliateCodeInfoIsOneSlot() public {
        address s = makeAddr("aff-upline2");
        address r = makeAddr("aff-upline1");
        address o = makeAddr("aff-owner");
        // r is referred by s's default code (s registers as its owner), o by r's (r registers).
        vm.prank(r);
        affiliate.referPlayer(bytes32(uint256(uint160(s))));
        vm.prank(o);
        affiliate.referPlayer(bytes32(uint256(uint160(r))));
        bytes32 code = bytes32("SLOTPROBE");
        vm.prank(o);
        affiliate.createAffiliateCode(code, 7);

        uint32 oId = game.walletIdOf(o);
        uint32 rId = game.walletIdOf(r);
        uint32 sId = game.walletIdOf(s);
        assertTrue(oId != 0 && rId != 0 && sId != 0, "owner and both uplines registered");

        bytes32 slot = keccak256(abi.encode(code, AFFILIATE_CODE));
        uint256 w = _load(address(affiliate), slot);
        assertEq(uint32(w), oId, "ownerId [0:32)");
        assertEq(uint8(w >> 32), 7, "kickback [32:40)");
        assertEq(uint32(w >> 40), rId, "upline1 [40:72)");
        assertEq(uint32(w >> 72), sId, "upline2 [72:104)");
        assertEq(uint8(w >> 104), 6, "flags [104:112): both upline caches valid");
        assertEq(w >> 112, 0, "nothing past bit 112");
        assertEq(_load(address(affiliate), _next(slot)), 0, "the next slot stays zero");

        (address owner, uint32 ownerId, uint8 kickback) = affiliate.affiliateCode(code);
        assertEq(owner, o, "view owner");
        assertEq(ownerId, oId, "view owner ID");
        assertEq(kickback, 7, "view kickback");
    }

    function test_wwxrpIncineratorEntryIsOneSlot() public {
        // A level-x99 burn doubles as a century incinerator entry for bracket x00.
        uint256 shift = GameSlots.LEVEL_OFFSET * 8;
        uint256 w0 = _load(address(game), bytes32(GameSlots.LEVEL));
        vm.store(address(game), bytes32(GameSlots.LEVEL),
            bytes32((w0 & ~(uint256(0xFFFFFF) << shift)) | (uint256(99) << shift)));
        assertEq(game.level(), 99, "level pinned to 99");

        address p = makeAddr("incin-0");
        address q = makeAddr("incin-1");
        vm.startPrank(address(game));
        wwxrp.mintPrize(p, 10_000);
        wwxrp.mintPrize(q, 10_000);
        vm.stopPrank();
        vm.prank(p);
        wwxrp.enter(1_000);
        vm.prank(q);
        wwxrp.enter(2_000);
        (, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(count, 2, "two incinerator entries");

        address[2] memory who = [p, q];
        for (uint32 i; i < 2; ++i) {
            bytes32 slot = keccak256(abi.encode((uint256(100) << 32) | i, WWXRP_INCIN_ENTRY));
            (uint32 id, uint256 cum) = wwxrp.incineratorEntryAt(100, i);
            assertEq(id, game.walletIdOf(who[i]), "entry holds the entrant's wallet ID");
            assertGt(cum, 0, "nonzero endpoint");
            assertEq(_load(address(wwxrp), slot), cum | (uint256(id) << 192), "one word: cum | id << 192");
            assertEq(_load(address(wwxrp), _next(slot)), 0, "the next slot stays untouched");
        }
    }

    function test_crapsIdWordIsOneSlot() public {
        address p = makeAddr("craps-id-word");
        uint32 id = _giveWalletId(p);
        uint32 chips = 1 | (1 << 9);
        vm.prank(p);
        crapsBattle.setPreferredBoard(chips);
        vm.prank(address(game));
        crapsBattle.creditPasses(id, 3, 2);

        uint256 root = crapsBattle.passCreditsByIdSlot();
        assertEq(root, CrapsSlots.PASS_CREDITS_BY_ID, "compiled root of _passCreditsById");
        assertEq(root, CrapsPreferenceLib.PASS_SLOT, "CrapsPreferenceLib.PASS_SLOT");
        bytes32 slot = keccak256(abi.encode(uint256(id), root));
        uint256 w = _load(address(crapsBattle), slot);
        assertEq(uint32(w), 3, "normal passes [0:32)");
        assertEq(uint32(w >> 32), 2, "high passes [32:64)");
        assertEq((w >> 64) & 0xFFFFF, CrapsPreferenceLib.compress(chips), "board [64:84)");
        assertEq((w >> 84) & 1, 1, "INITIALIZED [84]");
        assertEq(w >> 85, 0, "nothing above the initialized bit");
        assertEq(_load(address(crapsBattle), _next(slot)), 0, "the next slot stays untouched");

        uint256 addrRoot = crapsBattle.passCreditsSlot();
        assertEq(addrRoot, CrapsSlots.PASS_CREDITS, "compiled root of _passCredits");
        uint256 aw = _load(address(crapsBattle), keccak256(abi.encode(p, addrRoot)));
        assertEq(uint32(aw >> CrapsPreferenceLib.ID_SHIFT), id, "address word caches the ID [85:117)");
        assertEq(aw & type(uint64).max, 0, "address word carries no passes");
        assertEq(aw & CrapsPreferenceLib.MASK, w & CrapsPreferenceLib.MASK, "same board in both words");
        assertEq(aw >> 117, 0, "nothing above the cached ID");
    }
}
