// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title DeployCanary -- Validates all 23+5 addresses match patched constants
/// @notice If any assertion fails, the nonce prediction or deploy order is wrong.
contract DeployCanary is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }

    /// @notice Every deployed contract address must match its ContractAddresses constant
    function test_allAddressesMatch() public view {
        // Protocol contracts (23)
        assertEq(address(icons32), ContractAddresses.ICONS_32, "ICONS_32 mismatch");
        assertEq(address(mintModule), ContractAddresses.GAME_MINT_MODULE, "GAME_MINT_MODULE mismatch");
        assertEq(address(advanceModule), ContractAddresses.GAME_ADVANCE_MODULE, "GAME_ADVANCE_MODULE mismatch");
        assertEq(address(whaleModule), ContractAddresses.GAME_WHALE_MODULE, "GAME_WHALE_MODULE mismatch");
        assertEq(address(jackpotModule), ContractAddresses.GAME_JACKPOT_MODULE, "GAME_JACKPOT_MODULE mismatch");
        assertEq(address(decimatorModule), ContractAddresses.GAME_DECIMATOR_MODULE, "GAME_DECIMATOR_MODULE mismatch");
        assertEq(address(endgameModule), ContractAddresses.GAME_ENDGAME_MODULE, "GAME_ENDGAME_MODULE mismatch");
        assertEq(address(gameOverModule), ContractAddresses.GAME_GAMEOVER_MODULE, "GAME_GAMEOVER_MODULE mismatch");
        assertEq(address(lootboxModule), ContractAddresses.GAME_LOOTBOX_MODULE, "GAME_LOOTBOX_MODULE mismatch");
        assertEq(address(boonModule), ContractAddresses.GAME_BOON_MODULE, "GAME_BOON_MODULE mismatch");
        assertEq(address(degeneretteModule), ContractAddresses.GAME_DEGENERETTE_MODULE, "GAME_DEGENERETTE_MODULE mismatch");
        assertEq(address(coin), ContractAddresses.COIN, "COIN mismatch");
        assertEq(address(coinflip), ContractAddresses.COINFLIP, "COINFLIP mismatch");
        assertEq(address(game), ContractAddresses.GAME, "GAME mismatch");
        assertEq(address(wwxrp), ContractAddresses.WWXRP, "WWXRP mismatch");
        assertEq(address(affiliate), ContractAddresses.AFFILIATE, "AFFILIATE mismatch");
        assertEq(address(jackpots), ContractAddresses.JACKPOTS, "JACKPOTS mismatch");
        assertEq(address(quests), ContractAddresses.QUESTS, "QUESTS mismatch");
        assertEq(address(deityPass), ContractAddresses.DEITY_PASS, "DEITY_PASS mismatch");
        assertEq(address(vault), ContractAddresses.VAULT, "VAULT mismatch");
        assertEq(address(sdgnrs), ContractAddresses.SDGNRS, "SDGNRS mismatch");
        assertEq(address(dgnrs), ContractAddresses.DGNRS, "DGNRS mismatch");
        assertEq(address(admin), ContractAddresses.ADMIN, "ADMIN mismatch");

        // External/mock contracts (5)
        assertEq(address(mockVRF), ContractAddresses.VRF_COORDINATOR, "VRF_COORDINATOR mismatch");
        assertEq(address(mockStETH), ContractAddresses.STETH_TOKEN, "STETH_TOKEN mismatch");
        assertEq(address(mockLINK), ContractAddresses.LINK_TOKEN, "LINK_TOKEN mismatch");
        assertEq(address(mockWXRP), ContractAddresses.WXRP, "WXRP mismatch");

        // Creator is the test contract itself
        assertEq(address(this), ContractAddresses.CREATOR, "CREATOR mismatch");
    }

    /// @notice Constructor side effects must have executed correctly
    function test_protocolWired() public view {
        // Admin created a VRF subscription
        assertTrue(admin.subscriptionId() > 0, "No VRF subscription");

        // All key contracts are deployed (have code)
        assertTrue(address(game).code.length > 0, "Game not deployed");
        assertTrue(address(coin).code.length > 0, "Coin not deployed");
        assertTrue(address(vault).code.length > 0, "Vault not deployed");
        assertTrue(address(sdgnrs).code.length > 0, "SDGNRS not deployed");
        assertTrue(address(admin).code.length > 0, "Admin not deployed");
        assertTrue(address(coinflip).code.length > 0, "Coinflip not deployed");
    }
}
