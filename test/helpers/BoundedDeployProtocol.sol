// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGamePassModule} from "../../contracts/modules/DegenerusGamePassModule.sol";
import {DegenerusGameEndgameModule} from "../../contracts/modules/DegenerusGameEndgameModule.sol";
import {OwnerTargetCall} from "./OwnerTargetCall.sol";
import {RecyclingState} from "./RecyclingState.sol";

import "forge-std/Test.sol";

// Production contracts
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Icons32Data} from "../../contracts/Icons32Data.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {DegenerusGameDegenesisModule} from "../../contracts/modules/DegenerusGameDegenesisModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameDailyModule} from "../../contracts/modules/DegenerusGameDailyModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameDecimatorModule} from "../../contracts/modules/DegenerusGameDecimatorModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DegenerusGameDegeneretteModule} from "../../contracts/modules/DegenerusGameDegeneretteModule.sol";
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

        // BEGIN CANONICAL DEPLOYMENTS
        (address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,
            address[] memory players, bytes32[] memory refs) = _affiliateBootstrap();
        icons32 = Icons32Data(payable(deployCode("Icons32Data.sol:Icons32Data", abi.encode(false))));
        endgameModule = DegenerusGameEndgameModule(payable(deployCode("DegenerusGameEndgameModule.sol:DegenerusGameEndgameModule", abi.encode())));
        dailyModule = DegenerusGameDailyModule(payable(deployCode("DegenerusGameDailyModule.sol:DegenerusGameDailyModule", abi.encode())));
        passModule = DegenerusGamePassModule(payable(deployCode("DegenerusGamePassModule.sol:DegenerusGamePassModule", abi.encode())));
        boxModule = DegenerusGameBoxModule(payable(deployCode("DegenerusGameBoxModule.sol:DegenerusGameBoxModule", abi.encode())));
        coin = FLIP(payable(deployCode("FLIP.sol:FLIP", abi.encode())));
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1); // retired deployment nonce; retain token addresses
        game = DegenerusGame(payable(deployCode("DegenerusGame.sol:DegenerusGame", abi.encode())));
        coinflip = Coinflip(payable(deployCode("Coinflip.sol:Coinflip", abi.encode(owners, codes, kicks, players, refs))));
        jackpots = DegenerusJackpots(payable(deployCode("DegenerusJackpots.sol:DegenerusJackpots", abi.encode())));
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1); // retired deployment nonce; retain token addresses
        deityPass = DegenerusDeityPass(payable(deployCode("DegenerusDeityPass.sol:DegenerusDeityPass", abi.encode())));
        vault = DegenerusVault(payable(deployCode("DegenerusVault.sol:DegenerusVault", abi.encode())));
        sdgnrs = sDGNRS(payable(deployCode("sDGNRS.sol:sDGNRS", abi.encode())));
        dgnrs = DGNRS(payable(deployCode("DGNRS.sol:DGNRS", abi.encode())));
        admin = DegenerusAdmin(payable(deployCode("DegenerusAdmin.sol:DegenerusAdmin", abi.encode())));
        gnrus = GNRUS(payable(deployCode("GNRUS.sol:GNRUS", abi.encode())));
        afkingSubToken = AFKingSubscriptionToken(payable(deployCode("AFKingSubscriptionToken.sol:AFKingSubscriptionToken", abi.encode())));
        parimutuel = DegenerusParimutuel(payable(deployCode("DegenerusParimutuel.sol:DegenerusParimutuel", abi.encode())));
        recordBounty = DegenerusRecordBounty(payable(deployCode("DegenerusRecordBounty.sol:DegenerusRecordBounty", abi.encode())));
        crapsBattle = CrapsViews(payable(deployCode("CrapsViews.sol:CrapsViews", abi.encode())));
        wwxrp = WWXRP(payable(deployCode("WWXRP.sol:WWXRP", abi.encode())));
        ownerGovernance = DegenerusOwnerGovernance(payable(deployCode("DegenerusOwnerGovernance.sol:DegenerusOwnerGovernance", abi.encode())));
        mintModule = DegenerusGameMintModule(payable(address(endgameModule)));
        decimatorModule = DegenerusGameDecimatorModule(payable(address(endgameModule)));
        gameOverModule = DegenerusGameGameOverModule(payable(address(endgameModule)));
        foilModule = DegenerusGameFoilPackModule(payable(address(endgameModule)));
        degenesisModule = DegenerusGameDegenesisModule(payable(address(endgameModule)));
        advanceModule = DegenerusGameAdvanceModule(payable(address(dailyModule)));
        jackpotModule = DegenerusGameJackpotModule(payable(address(dailyModule)));
        rngModule = DegenerusGameRngModule(payable(address(dailyModule)));
        jackpotDrawModule = DegenerusGameJackpotDrawModule(payable(address(dailyModule)));
        whaleModule = DegenerusGameWhaleModule(payable(address(passModule)));
        ticketModule = DegenerusGameTicketModule(payable(address(passModule)));
        lootboxModule = DegenerusGameLootboxModule(payable(address(boxModule)));
        boonModule = DegenerusGameBoonModule(payable(address(boxModule)));
        degeneretteModule = DegenerusGameDegeneretteModule(payable(address(boxModule)));
        afkingModule = GameAfkingModule(payable(address(boxModule)));
        bingoModule = DegenerusGame(payable(address(game)));
        minerModule = DegenerusGame(payable(address(game)));
        affiliate = DegenerusAffiliate(payable(address(coinflip)));
        quests = DegenerusQuests(payable(address(coinflip)));
        crapsEngine = CrapsEngine(payable(address(crapsBattle)));
        jackpotBattle = JackpotBattle(payable(address(crapsBattle)));
        // END CANONICAL DEPLOYMENTS
        uint24 fixtureDay = _deployDay();
        if (fixtureDay != 1) {
            _seedLogicalFixtureDay(fixtureDay);
            _seedCrapsFixtureCursor(fixtureDay);
        }
        if (initializeDeities) game.initProtocolDeity();
    }
}
