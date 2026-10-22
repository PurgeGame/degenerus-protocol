// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {OwnerTargetCall} from "./OwnerTargetCall.sol";
import {RecyclingState} from "./RecyclingState.sol";

import "forge-std/Test.sol";

// Production contracts
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Icons32Data} from "../../contracts/Icons32Data.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameDegenesisModule} from "../../contracts/modules/DegenerusGameDegenesisModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
import {DegenerusGameBingoModule} from "../../contracts/modules/DegenerusGameBingoModule.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {DegenerusParimutuel} from "../../contracts/DegenerusParimutuel.sol";
import {DegenerusRecordBounty} from "../../contracts/DegenerusRecordBounty.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IDegenerusGameLootboxModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {DegenerusAffiliate} from "../../contracts/DegenerusAffiliate.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {DegenerusDeityPass} from "../../contracts/DegenerusDeityPass.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DGNRS} from "../../contracts/DGNRS.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {DegenerusOwnerGovernance} from "../../contracts/DegenerusOwnerGovernance.sol";
import {GNRUS} from "../../contracts/GNRUS.sol";

// Mock contracts
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../contracts/mocks/MockStETH.sol";
import {MockLinkToken} from "../../contracts/mocks/MockLinkToken.sol";
import {MockLinkEthFeed} from "../../contracts/mocks/MockLinkEthFeed.sol";
import {GameSlots, GameSlotKeys} from "./GameSlots.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @dev Deploy current compiler artifacts without embedding every creation bytecode
///      into each benchmark contract. CREATE order is identical to DeployProtocol.
abstract contract BoundedDeployProtocol is DeployProtocol {
    function _deployBounded(bool initializeDeities) internal {
        vm.warp(_deployTimestamp());

        mockVRF = MockVRFCoordinator(payable(deployCode("MockVRFCoordinator.sol:MockVRFCoordinator", abi.encode())));           // nonce 1
        mockStETH = MockStETH(payable(deployCode("MockStETH.sol:MockStETH", abi.encode())));                  // nonce 2
        mockLINK = MockLinkToken(payable(deployCode("MockLinkToken.sol:MockLinkToken", abi.encode())));               // nonce 3
        mockFeed = MockLinkEthFeed(payable(deployCode("MockLinkEthFeed.sol:MockLinkEthFeed", abi.encode(int256(0.004 ether))))); // nonce 4

        icons32 = Icons32Data(payable(deployCode("Icons32Data.sol:Icons32Data", abi.encode(false))));                   // N+0 = nonce 5
        mintModule = DegenerusGameMintModule(payable(deployCode("DegenerusGameMintModule.sol:DegenerusGameMintModule", abi.encode())));    // N+1 = nonce 6
        advanceModule = DegenerusGameAdvanceModule(payable(deployCode("DegenerusGameAdvanceModule.sol:DegenerusGameAdvanceModule", abi.encode()))); // N+2 = nonce 7
        whaleModule = DegenerusGameWhaleModule(payable(deployCode("DegenerusGameWhaleModule.sol:DegenerusGameWhaleModule", abi.encode())));  // N+3 = nonce 8
        jackpotModule = DegenerusGameJackpotModule(payable(deployCode("DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule", abi.encode()))); // N+4 = nonce 9
        decimatorModule = DegenerusGameDecimatorModule(payable(deployCode("DegenerusGameDecimatorModule.sol:DegenerusGameDecimatorModule", abi.encode()))); // N+5 = nonce 10
        gameOverModule = DegenerusGameGameOverModule(payable(deployCode("DegenerusGameGameOverModule.sol:DegenerusGameGameOverModule", abi.encode()))); // N+6 = nonce 11
        lootboxModule = DegenerusGameLootboxModule(payable(deployCode("DegenerusGameLootboxModule.sol:DegenerusGameLootboxModule", abi.encode()))); // N+7 = nonce 12
        boonModule = DegenerusGameBoonModule(payable(deployCode("DegenerusGameBoonModule.sol:DegenerusGameBoonModule", abi.encode())));    // N+8 = nonce 13
        degeneretteModule = DegenerusGameDegeneretteModule(payable(deployCode("DegenerusGameDegeneretteModule.sol:DegenerusGameDegeneretteModule", abi.encode()))); // N+9 = nonce 14

        bingoModule = DegenerusGameBingoModule(payable(deployCode("DegenerusGameBingoModule.sol:DegenerusGameBingoModule", abi.encode())));  // N+10 = nonce 15
        afkingModule = GameAfkingModule(payable(deployCode("GameAfkingModule.sol:GameAfkingModule", abi.encode())));         // N+11 = nonce 16

        coin = FLIP(payable(deployCode("FLIP.sol:FLIP", abi.encode())));                       // N+12 = nonce 17

        coinflip = Coinflip(payable(deployCode("Coinflip.sol:Coinflip", abi.encode())));                // N+13 = nonce 18

        game = DegenerusGame(payable(deployCode("DegenerusGame.sol:DegenerusGame", abi.encode())));                    // N+14 = nonce 19
        ticketModule = DegenerusGameTicketModule(payable(deployCode("DegenerusGameTicketModule.sol:DegenerusGameTicketModule", abi.encode()))); // N+15 = nonce 20

        (address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
            address[] memory players, bytes32[] memory refs) = _affiliateBootstrap();
        affiliate = DegenerusAffiliate(payable(deployCode("DegenerusAffiliate.sol:DegenerusAffiliate", abi.encode(owners, codes, kicks, players, refs)))); // N+16

        jackpots = DegenerusJackpots(payable(deployCode("DegenerusJackpots.sol:DegenerusJackpots", abi.encode())));            // N+17 = nonce 22
        quests = DegenerusQuests(payable(deployCode("DegenerusQuests.sol:DegenerusQuests", abi.encode())));                // N+18 = nonce 23
        deityPass = DegenerusDeityPass(payable(deployCode("DegenerusDeityPass.sol:DegenerusDeityPass", abi.encode())));          // N+19 = nonce 24

        vault = DegenerusVault(payable(deployCode("DegenerusVault.sol:DegenerusVault", abi.encode())));                  // N+20 = nonce 25

        sdgnrs = sDGNRS(payable(deployCode("sDGNRS.sol:sDGNRS", abi.encode())));           // N+21 = nonce 26

        dgnrs = DGNRS(payable(deployCode("DGNRS.sol:DGNRS", abi.encode())));                  // N+22 = nonce 27

        admin = DegenerusAdmin(payable(deployCode("DegenerusAdmin.sol:DegenerusAdmin", abi.encode())));                  // N+23 = nonce 28

        gnrus = GNRUS(payable(deployCode("GNRUS.sol:GNRUS", abi.encode())));                            // N+24 = nonce 29

        foilModule = DegenerusGameFoilPackModule(payable(deployCode("DegenerusGameFoilPackModule.sol:DegenerusGameFoilPackModule", abi.encode()))); // N+25 = nonce 30

        afkingSubToken = AFKingSubscriptionToken(payable(deployCode("AFKingSubscriptionToken.sol:AFKingSubscriptionToken", abi.encode())));                  // N+26 = nonce 31

        parimutuel = DegenerusParimutuel(payable(deployCode("DegenerusParimutuel.sol:DegenerusParimutuel", abi.encode())));                          // N+27 = nonce 32

        recordBounty = DegenerusRecordBounty(payable(deployCode("DegenerusRecordBounty.sol:DegenerusRecordBounty", abi.encode())));                      // N+28 = nonce 33

        crapsBattle = CrapsViews(payable(deployCode("CrapsViews.sol:CrapsViews", abi.encode())));                                     // N+29 = nonce 34

        crapsEngine = CrapsEngine(payable(deployCode("CrapsEngine.sol:CrapsEngine", abi.encode())));                                    // N+30 = nonce 35

        jackpotBattle = JackpotBattle(payable(deployCode("JackpotBattle.sol:JackpotBattle", abi.encode())));                              // N+31 = nonce 36
        wwxrp = WWXRP(payable(deployCode("WWXRP.sol:WWXRP", abi.encode()))); // N+32 = nonce 37
        minerModule = DegenerusGameMinerModule(payable(deployCode("DegenerusGameMinerModule.sol:DegenerusGameMinerModule", abi.encode())));                      // N+33 = nonce 38
        rngModule = DegenerusGameRngModule(payable(deployCode("DegenerusGameRngModule.sol:DegenerusGameRngModule", abi.encode())));                          // N+34 = nonce 39
        jackpotDrawModule = DegenerusGameJackpotDrawModule(payable(deployCode("DegenerusGameJackpotDrawModule.sol:DegenerusGameJackpotDrawModule", abi.encode())));          // N+35 = nonce 40
        degenesisModule = DegenerusGameDegenesisModule(payable(deployCode("DegenerusGameDegenesisModule.sol:DegenerusGameDegenesisModule", abi.encode())));              // N+36 = nonce 41
        ownerGovernance = DegenerusOwnerGovernance(payable(deployCode("DegenerusOwnerGovernance.sol:DegenerusOwnerGovernance", abi.encode()))); // N+37; preserve all prior CREATE nonces
        if (initializeDeities) game.initProtocolDeity();
    }
}
