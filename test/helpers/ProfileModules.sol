// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

// Generated selected worker runtimes for standalone fixtures; no storage initialization.
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Eip170Actions} from "../../contracts/profiles/eip170/Eip170Actions.sol";
import {Eip170Purchase} from "../../contracts/profiles/eip170/Eip170Purchase.sol";
import {Eip170Mint} from "../../contracts/profiles/eip170/Eip170Mint.sol";
import {Eip170DegenesisFoil} from "../../contracts/profiles/eip170/Eip170DegenesisFoil.sol";
import {Eip170Advance} from "../../contracts/profiles/eip170/Eip170Advance.sol";
import {Eip170Jackpot} from "../../contracts/profiles/eip170/Eip170Jackpot.sol";
import {Eip170JackpotDraw} from "../../contracts/profiles/eip170/Eip170JackpotDraw.sol";
import {Eip170Whale} from "../../contracts/profiles/eip170/Eip170Whale.sol";
import {Eip170TicketFoil} from "../../contracts/profiles/eip170/Eip170TicketFoil.sol";
import {Eip170Lootbox} from "../../contracts/profiles/eip170/Eip170Lootbox.sol";
import {Eip170Boon} from "../../contracts/profiles/eip170/Eip170Boon.sol";
import {Eip170Degenerette} from "../../contracts/profiles/eip170/Eip170Degenerette.sol";
import {Eip170Afking} from "../../contracts/profiles/eip170/Eip170Afking.sol";
import {Eip170Endgame} from "../../contracts/profiles/eip170/Eip170Endgame.sol";
import {Eip170Decimator} from "../../contracts/profiles/eip170/Eip170Decimator.sol";
import {Eip170MinerRng} from "../../contracts/profiles/eip170/Eip170MinerRng.sol";
import {Eip170CrapsEngine} from "../../contracts/profiles/eip170/Eip170CrapsEngine.sol";
import {Eip170JackpotBattle} from "../../contracts/profiles/eip170/Eip170JackpotBattle.sol";

library ProfileModules {
    function installGame(Vm vm) internal {
        vm.etch(ContractAddresses.GAME_ACTIONS_MODULE, vm.getDeployedCode("Eip170Actions.sol:Eip170Actions"));
        vm.etch(ContractAddresses.GAME_PURCHASE_MODULE, vm.getDeployedCode("Eip170Purchase.sol:Eip170Purchase"));
        vm.etch(ContractAddresses.GAME_MINT_MODULE, vm.getDeployedCode("Eip170Mint.sol:Eip170Mint"));
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, vm.getDeployedCode("Eip170DegenesisFoil.sol:Eip170DegenesisFoil"));
        vm.etch(ContractAddresses.GAME_ADVANCE_MODULE, vm.getDeployedCode("Eip170Advance.sol:Eip170Advance"));
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, vm.getDeployedCode("Eip170Jackpot.sol:Eip170Jackpot"));
        vm.etch(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, vm.getDeployedCode("Eip170JackpotDraw.sol:Eip170JackpotDraw"));
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, vm.getDeployedCode("Eip170Whale.sol:Eip170Whale"));
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, vm.getDeployedCode("Eip170TicketFoil.sol:Eip170TicketFoil"));
        vm.etch(ContractAddresses.GAME_LOOTBOX_MODULE, vm.getDeployedCode("Eip170Lootbox.sol:Eip170Lootbox"));
        vm.etch(ContractAddresses.GAME_BOON_MODULE, vm.getDeployedCode("Eip170Boon.sol:Eip170Boon"));
        vm.etch(ContractAddresses.GAME_DEGENERETTE_MODULE, vm.getDeployedCode("Eip170Degenerette.sol:Eip170Degenerette"));
        vm.etch(ContractAddresses.GAME_AFKING_MODULE, vm.getDeployedCode("Eip170Afking.sol:Eip170Afking"));
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, vm.getDeployedCode("Eip170Endgame.sol:Eip170Endgame"));
        vm.etch(ContractAddresses.GAME_DECIMATOR_MODULE, vm.getDeployedCode("Eip170Decimator.sol:Eip170Decimator"));
        vm.etch(ContractAddresses.GAME_MINER_MODULE, vm.getDeployedCode("Eip170MinerRng.sol:Eip170MinerRng"));
    }
    function installCraps(Vm vm) internal {
        vm.etch(ContractAddresses.CRAPS_ENGINE, vm.getDeployedCode("Eip170CrapsEngine.sol:Eip170CrapsEngine"));
        vm.etch(ContractAddresses.CRAPS_LIFECYCLE_MODULE, vm.getDeployedCode("Eip170JackpotBattle.sol:Eip170JackpotBattle"));
    }
}
