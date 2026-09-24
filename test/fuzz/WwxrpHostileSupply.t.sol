// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title WwxrpHostileSupply — a hostile WWXRP authority cannot brick the game.
///
/// @notice The vault owner can mint WWXRP freely. Minting the supply to its ceiling used to make
///         every later mint panic on overflow, including the ones the daily advance makes itself
///         (Coinflip's loss reward to sDGNRS on a day its flip loses). `WWXRP._mint` saturates, so
///         the advance keeps running and later mints simply mint what fits.
contract WwxrpHostileSupply is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000 ether);
        require(vault.isVaultOwner(ContractAddresses.CREATOR), "fixture: CREATOR owns the vault");
    }

    function _fulfill() internal {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (!done) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, vm.getBlockTimestamp()))));
    }

    /// @dev Crank one wall day to its seal; returns false if any advance reverted for a reason
    ///      other than "nothing to do".
    function _runDay() internal returns (bool clean) {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 200; ++i) {
            _fulfill();
            (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) {
                bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
                return sel == bytes4(keccak256("NotTimeYet()"));
            }
            if (!game.rngLocked() && !game.advanceDue()) return true;
        }
        return false;
    }

    function test_supplyAtCeilingDoesNotBrickTheAdvance() public {
        // The vault owner (this contract) mints the whole remaining supply range to itself.
        wwxrp.vaultMintTo(address(this), type(uint256).max - wwxrp.totalSupply());
        assertEq(wwxrp.totalSupply(), type(uint256).max, "harness: supply at the ceiling");

        // Thirty real days: sDGNRS's seeded coinflip stake loses on about half of them, and each
        // loss mints WWXRP inside the advance. Every day must still seal.
        uint256 sdBefore = wwxrp.balanceOf(ContractAddresses.SDGNRS);
        for (uint256 d; d < 30; ++d) {
            assertTrue(_runDay(), "an advance reverted with WWXRP at its supply ceiling");
        }
        assertEq(wwxrp.balanceOf(ContractAddresses.SDGNRS), sdBefore, "no room left, so nothing was minted");
        assertFalse(game.gameOver(), "the game is still live");
    }

    function test_mintPastTheCeilingSaturates() public {
        wwxrp.vaultMintTo(address(this), type(uint256).max - wwxrp.totalSupply());
        wwxrp.vaultMintTo(address(0xBEEF), 1 ether);
        assertEq(wwxrp.totalSupply(), type(uint256).max, "a mint past the ceiling mints nothing");
        assertEq(wwxrp.balanceOf(address(0xBEEF)), 0, "and credits nobody");
    }
}
