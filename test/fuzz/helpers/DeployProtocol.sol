// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

// Production contracts
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {Icons32Data} from "../../../contracts/Icons32Data.sol";
import {DegenerusGameMintModule} from "../../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameAdvanceModule} from "../../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameWhaleModule} from "../../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameEndgameModule} from "../../../contracts/modules/DegenerusGameEndgameModule.sol";
import {DegenerusGameGameOverModule} from "../../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameLootboxModule} from "../../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";
import {BurnieCoinflip} from "../../../contracts/BurnieCoinflip.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {WrappedWrappedXRP} from "../../../contracts/WrappedWrappedXRP.sol";
import {DegenerusAffiliate} from "../../../contracts/DegenerusAffiliate.sol";
import {DegenerusJackpots} from "../../../contracts/DegenerusJackpots.sol";
import {DegenerusQuests} from "../../../contracts/DegenerusQuests.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {StakedDegenerusStonk} from "../../../contracts/StakedDegenerusStonk.sol";
import {DegenerusStonk} from "../../../contracts/DegenerusStonk.sol";
import {DegenerusAdmin} from "../../../contracts/DegenerusAdmin.sol";
import {DegenerusCharity} from "../../../contracts/DegenerusCharity.sol";

// Mock contracts
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {MockLinkToken} from "../../../contracts/mocks/MockLinkToken.sol";
import {MockWXRP} from "../../../contracts/mocks/MockWXRP.sol";
import {MockLinkEthFeed} from "../../../contracts/mocks/MockLinkEthFeed.sol";

/// @title DeployProtocol -- Abstract base for Foundry invariant tests
/// @notice Deploys all 5 mocks + 24 protocol contracts in setUp().
///         Inherit this, call _deployProtocol() in your setUp().
/// @dev Address correctness depends on patchForFoundry.js having patched
///      ContractAddresses.sol before forge build.
abstract contract DeployProtocol is Test {
    // Mocks
    MockVRFCoordinator public mockVRF;
    MockStETH public mockStETH;
    MockLinkToken public mockLINK;
    MockWXRP public mockWXRP;
    MockLinkEthFeed public mockFeed;

    // Protocol contracts
    Icons32Data public icons32;
    DegenerusGameMintModule public mintModule;
    DegenerusGameAdvanceModule public advanceModule;
    DegenerusGameWhaleModule public whaleModule;
    DegenerusGameJackpotModule public jackpotModule;
    DegenerusGameDecimatorModule public decimatorModule;
    DegenerusGameEndgameModule public endgameModule;
    DegenerusGameGameOverModule public gameOverModule;
    DegenerusGameLootboxModule public lootboxModule;
    DegenerusGameBoonModule public boonModule;
    DegenerusGameDegeneretteModule public degeneretteModule;
    BurnieCoin public coin;
    BurnieCoinflip public coinflip;
    DegenerusGame public game;
    WrappedWrappedXRP public wwxrp;
    DegenerusAffiliate public affiliate;
    DegenerusJackpots public jackpots;
    DegenerusQuests public quests;
    DegenerusDeityPass public deityPass;
    DegenerusVault public vault;
    StakedDegenerusStonk public sdgnrs;
    DegenerusStonk public dgnrs;
    DegenerusAdmin public admin;
    DegenerusCharity public gnrus;

    /// @notice Deploy the full protocol. Must be called from setUp().
    /// @dev Uses vm.warp(86400) to match the fixed timestamp in patchForFoundry.js.
    function _deployProtocol() internal {
        // Set timestamp to match patchForFoundry.js DEPLOY_TIMESTAMP = 86400
        vm.warp(86400);

        // --- Deploy 5 mocks (nonces 1-5) ---
        // Then 24 protocol contracts (nonces 6-29) ---
        mockVRF = new MockVRFCoordinator();           // nonce 1
        mockStETH = new MockStETH();                  // nonce 2
        mockLINK = new MockLinkToken();               // nonce 3
        mockWXRP = new MockWXRP();                    // nonce 4
        mockFeed = new MockLinkEthFeed(int256(0.004 ether)); // nonce 5

        // Order matches DEPLOY_ORDER in predictAddresses.js

        icons32 = new Icons32Data();                   // N+0 = nonce 6
        mintModule = new DegenerusGameMintModule();    // N+1 = nonce 7
        advanceModule = new DegenerusGameAdvanceModule(); // N+2 = nonce 8
        whaleModule = new DegenerusGameWhaleModule();  // N+3 = nonce 9
        jackpotModule = new DegenerusGameJackpotModule(); // N+4 = nonce 10
        decimatorModule = new DegenerusGameDecimatorModule(); // N+5 = nonce 11
        endgameModule = new DegenerusGameEndgameModule(); // N+6 = nonce 12
        gameOverModule = new DegenerusGameGameOverModule(); // N+7 = nonce 13
        lootboxModule = new DegenerusGameLootboxModule(); // N+8 = nonce 14
        boonModule = new DegenerusGameBoonModule();    // N+9 = nonce 15
        degeneretteModule = new DegenerusGameDegeneretteModule(); // N+10 = nonce 16

        coin = new BurnieCoin();                       // N+11 = nonce 17

        // BurnieCoinflip needs constructor args (uses patched ContractAddresses)
        coinflip = new BurnieCoinflip(
            ContractAddresses.COIN,
            ContractAddresses.GAME,
            ContractAddresses.JACKPOTS,
            ContractAddresses.WWXRP
        );                                             // N+12 = nonce 18

        game = new DegenerusGame();                    // N+13 = nonce 19
        wwxrp = new WrappedWrappedXRP();               // N+14 = nonce 20

        // DegenerusAffiliate needs empty arrays
        affiliate = new DegenerusAffiliate(
            new address[](0),
            new bytes32[](0),
            new uint8[](0),
            new address[](0),
            new bytes32[](0)
        );                                             // N+15 = nonce 21

        jackpots = new DegenerusJackpots();            // N+16 = nonce 22
        quests = new DegenerusQuests();                // N+17 = nonce 23
        deityPass = new DegenerusDeityPass();          // N+18 = nonce 24

        // Vault constructor calls COIN.vaultMintAllowance()
        vault = new DegenerusVault();                  // N+19 = nonce 25

        // Stonk constructor calls GAME.claimWhalePass() + GAME.setAfKingMode()
        // Mints creator's 20% to DGNRS address
        sdgnrs = new StakedDegenerusStonk();           // N+20 = nonce 26

        // DGNRS reads its sDGNRS balance and mints DGNRS to CREATOR
        dgnrs = new DegenerusStonk();                  // N+21 = nonce 27

        // Admin constructor calls VRF.createSubscription() + GAME.wireVrf()
        admin = new DegenerusAdmin();                  // N+22 = nonce 28

        // GNRUS: self-mints 1T to address(this), no cross-contract constructor calls
        gnrus = new DegenerusCharity();                // N+23 = nonce 29
    }
}
