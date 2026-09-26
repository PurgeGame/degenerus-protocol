// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title WwxrpTrustedMintersTest -- the vault owner's trusted minter/burner registry on WWXRP.
/// @notice The vault owner (>50.1% of DGVE) may register any address to mint through mintPrize,
///         burn through burnForGame and consume WWXRP boons through consumeBoon, exactly as the
///         pinned game contracts can, and may revoke it again. Nobody else may register, and an
///         unregistered address keeps the old reverts. Boon consumption needs no player approval
///         and reaches only the WWXRP boon lane.
contract WwxrpTrustedMintersTest is DeployProtocol {
    // --- boonPacked[player].slot1 lanes (mirror DegeneretteBoonStake) ---
    uint256 private constant SLOT_BOON_PACKED = 50;
    uint256 private constant ETH_LANE_SHIFT = 184;
    uint256 private constant WWXRP_LANE_SHIFT = 232;
    uint256 private constant LANE_MASK = 0xFFFFFF;
    uint256 private constant LANE_DAY_SHIFT = 3;

    address private owner;
    address private stranger;
    address private futureGame;
    address private player;

    event TrustedMinterSet(address indexed account, bool trusted);

    function setUp() public {
        _deployProtocol();
        owner = makeAddr("wwxrp_vault_owner");
        stranger = makeAddr("wwxrp_stranger");
        futureGame = makeAddr("wwxrp_future_game");
        player = makeAddr("wwxrp_player");
        // Vault ownership is a DGVE-majority check on the vault; mock it for `owner` only.
        vm.mockCall(
            ContractAddresses.VAULT,
            abi.encodeWithSignature("isVaultOwner(address)", owner),
            abi.encode(true)
        );
    }

    function testOnlyTheVaultOwnerRegisters() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        wwxrp.setTrustedMinter(futureGame, true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        wwxrp.setTrustedMinter(address(0), true);

        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit TrustedMinterSet(futureGame, true);
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);
        assertTrue(wwxrp.trustedMinter(futureGame), "registered");
    }

    function testUnregisteredAddressStillCannotMintOrBurn() public {
        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.mintPrize(player, 1 ether);

        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.burnForGame(player, 1 ether);
    }

    function testTrustedAddressMintsAndBurnsLikeTheGame() public {
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);

        uint256 supplyBefore = wwxrp.totalSupply();
        vm.prank(futureGame);
        wwxrp.mintPrize(player, 500 ether);
        assertEq(wwxrp.balanceOf(player), 500 ether, "minted to the player");
        assertEq(wwxrp.totalSupply(), supplyBefore + 500 ether, "supply grew");

        vm.prank(futureGame);
        wwxrp.burnForGame(player, 200 ether);
        assertEq(wwxrp.balanceOf(player), 300 ether, "burned from the player");
        assertEq(wwxrp.totalSupply(), supplyBefore + 300 ether, "supply shrank");

        // Zero-amount burn is a silent no-op, as for the game.
        vm.prank(futureGame);
        wwxrp.burnForGame(player, 0);
        assertEq(wwxrp.balanceOf(player), 300 ether, "zero burn is a no-op");
    }

    function testRevokedAddressLosesBothPowers() public {
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);
        vm.prank(futureGame);
        wwxrp.mintPrize(player, 1 ether);

        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit TrustedMinterSet(futureGame, false);
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, false);
        assertFalse(wwxrp.trustedMinter(futureGame), "revoked");

        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.mintPrize(player, 1 ether);
        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.burnForGame(player, 1 ether);
    }

    function testPinnedMintersAreUnaffected() public {
        vm.prank(ContractAddresses.GAME);
        wwxrp.mintPrize(player, 7 ether);
        assertEq(wwxrp.balanceOf(player), 7 ether, "the game still mints");
        vm.prank(ContractAddresses.GAME);
        wwxrp.burnForGame(player, 7 ether);
        assertEq(wwxrp.balanceOf(player), 0, "the game still burns");
        assertFalse(wwxrp.trustedMinter(ContractAddresses.GAME), "pinned minters are not registry entries");
    }

    function testUnregisteredAddressCannotConsumeBoons() public {
        _grantLane(player, WWXRP_LANE_SHIFT, 2);
        uint256 before = _slot1(player);

        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.consumeBoon(player);
        assertEq(_slot1(player), before, "boon untouched");
    }

    function testTrustedAddressConsumesBoonWithoutPlayerApproval() public {
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);
        _grantLane(player, WWXRP_LANE_SHIFT, 3);
        _grantLane(player, ETH_LANE_SHIFT, 1);
        _grantLane(player, 0, 2); // craps lane (slot1 low 24 bits)
        // Every slot0 boon (coinflip, purchase, decimator, lootbox, passes) as a raw pattern.
        uint256 s0 = uint256(keccak256("wwxrp_other_boons"));
        vm.store(address(game), _slot0Key(player), bytes32(s0));
        uint256 othersBefore = _slot1(player) & ((uint256(1) << WWXRP_LANE_SHIFT) - 1);

        vm.prank(futureGame);
        assertEq(wwxrp.consumeBoon(player), 1200, "tier 3 pays +12%");
        uint256 s1 = _slot1(player);
        assertEq((s1 >> WWXRP_LANE_SHIFT) & LANE_MASK, 0, "WWXRP lane spent");
        assertEq(s1, othersBefore, "craps/ETH/FLIP lanes untouched");
        assertEq(uint256(vm.load(address(game), _slot0Key(player))), s0, "slot0 boons untouched");

        vm.prank(futureGame);
        assertEq(wwxrp.consumeBoon(player), 0, "boon spends once");
    }

    function testRevokedAddressCannotConsumeBoons() public {
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, false);
        _grantLane(player, WWXRP_LANE_SHIFT, 1);

        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.consumeBoon(player);
    }

    function _slot1(address who) private view returns (uint256) {
        return uint256(vm.load(address(game), _slot1Key(who)));
    }

    function _slot0Key(address who) private pure returns (bytes32) {
        return keccak256(abi.encode(who, SLOT_BOON_PACKED));
    }

    function _slot1Key(address who) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(who, SLOT_BOON_PACKED))) + 1);
    }

    /// @dev Write a lootbox-rolled (non-deity) lane stamped today; other lanes are kept.
    function _grantLane(address who, uint256 shift, uint8 tier) private {
        uint256 lane = (uint256(game.currentDayView() & 0x1FFFFF) << LANE_DAY_SHIFT) | tier;
        uint256 s1 = (_slot1(who) & ~(LANE_MASK << shift)) | (lane << shift);
        vm.store(address(game), _slot1Key(who), bytes32(s1));
    }
}
