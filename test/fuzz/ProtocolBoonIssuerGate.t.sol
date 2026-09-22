// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @dev Sets the deity ownership bit exactly as a paid deity purchase does.
contract IssuerGateFixture is DegenerusGameStorage {
    function grantDeityBit(address who) external {
        mintPacked_[who] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
    }
}

/// @notice A paid deity holder must not be able to reach the protocol boon draw as an issuer.
contract ProtocolBoonIssuerGateTest is DeployProtocol {
    IssuerGateFixture private fixture;
    address private donor;
    address private deityHolder;

    function setUp() public {
        _deployProtocol();
        fixture = new IssuerGateFixture();
        vm.warp(block.timestamp + 1 days);
        donor = makeAddr("donor");
        deityHolder = makeAddr("deityHolder");
        vm.prank(address(game)); coin.mintForGame(donor, 1_000_000 ether);
        bytes memory original = address(game).code;
        vm.etch(address(game), address(fixture).code);
        (bool ok,) = address(game).call(abi.encodeCall(IssuerGateFixture.grantDeityBit, (deityHolder)));
        require(ok, "fixture");
        vm.etch(address(game), original);
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, donor), abi.encode(uint256(0)));
    }

    function test_PaidDeityHolderCannotDrainAnotherPlayersFlip() public {
        uint256 donorBefore = coin.balanceOf(donor);
        uint256 holderStakeBefore = coinflip.coinflipAmount(deityHolder);
        vm.prank(deityHolder);
        (bool ok,) = address(game).call(abi.encodeWithSignature("enterProtocolBoonDraw(address,uint256)", donor, 25_000 ether));
        emit log_named_uint("donor_flip_lost", donorBefore - coin.balanceOf(donor));
        emit log_named_uint("holder_stake_gained", coinflip.coinflipAmount(deityHolder) - holderStakeBefore);
        assertFalse(ok, "the removed donation selector remains reachable");
        assertEq(coin.balanceOf(donor), donorBefore, "donor FLIP was burned without consent");
    }

    function testRemovedDonationWrappersAndModuleEntryRejectCalls() public {
        uint256 balance = coin.balanceOf(donor);
        bytes memory donation = abi.encodeWithSignature("donateFlipForBoons(uint256)", 100 ether);
        vm.prank(donor);
        (bool ok,) = address(vault).call(donation);
        assertFalse(ok);
        vm.prank(donor);
        (ok,) = address(sdgnrs).call(donation);
        assertFalse(ok);
        vm.prank(address(vault));
        (ok,) = address(boonModule).call(abi.encodeWithSignature("enterProtocolBoonDraw(address,uint256)", donor, 100 ether));
        assertFalse(ok);
        assertEq(coin.balanceOf(donor), balance);
    }
}
