// Interface coverage follows the actual deployed host for the selected profile.
import fs from "node:fs";
import path from "node:path";
import { PROFILES, PROFILE } from "./deploymentProfiles.js";

const targets = {
  "contracts/interfaces/ILiquidation.sol:IDeityPassSeize": "DEITY_PASS",
  "contracts/interfaces/ICoinflip.sol:ICoinflip": "COINFLIP",
  "contracts/interfaces/IDegenerusAffiliate.sol:IDegenerusAffiliate": "AFFILIATE",
  "contracts/interfaces/IDegenerusCoin.sol:IDegenerusCoin": "COIN",
  "contracts/interfaces/IDegenerusGame.sol:IDegenerusGame": "GAME",
  "contracts/interfaces/IDegenerusJackpots.sol:IDegenerusJackpots": "JACKPOTS",
  "contracts/interfaces/IDegenerusParimutuel.sol:IDegenerusParimutuel": "PARIMUTUEL",
  "contracts/interfaces/IDegenerusQuests.sol:IDegenerusQuests": "QUESTS",
  "contracts/interfaces/IJackpotBattle.sol:IJackpotBattle": "JACKPOT_BATTLE",
  "contracts/interfaces/IsDGNRS.sol:IsDGNRS": "SDGNRS",
  "contracts/interfaces/IVaultCoin.sol:IVaultCoin": "COIN",
  "contracts/interfaces/IOwnerActions.sol:IOwnerVault": "VAULT",
  "contracts/interfaces/IVaultPlayerActions.sol:IVaultAffiliateClaim": "GAME",
  "contracts/interfaces/IVaultPlayerActions.sol:IVaultBatchAffiliateClaim": "GAME",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameAdvanceModule": "GAME_ADVANCE_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameMinerModule": "GAME_MINER_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameRngModule": "GAME_RNG_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameTicketModule": "GAME_TICKET_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameJackpotDrawModule": "GAME_JACKPOT_DRAW_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameGameOverModule": "GAME_GAMEOVER_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameJackpotModule": "GAME_JACKPOT_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameDecimatorModule": "GAME_DECIMATOR_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameWhaleModule": "GAME_WHALE_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameMintModule": "GAME_MINT_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameLootboxModule": "GAME_LOOTBOX_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameBoonModule": "GAME_BOON_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameDegeneretteModule": "GAME_DEGENERETTE_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameBingoModule": "GAME_BINGO_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IGameAfkingModule": "GAME_AFKING_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameFoilPackModule": "GAME_FOILPACK_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameFoilWorkerModule": "GAME_TICKET_MODULE",
  "contracts/interfaces/IDegenerusGameModules.sol:IDegenerusGameDegenesisModule": "GAME_DEGENESIS_MODULE",
  "contracts/interfaces/IGameEntryModules.sol:IGamePurchaseModule": "GAME_PURCHASE_MODULE",
  "contracts/interfaces/IGameEntryModules.sol:IGameMinerModule": "GAME_MINER_MODULE",
  "contracts/interfaces/IGameEntryModules.sol:IGameBingoModule": "GAME_BINGO_MODULE",
  "contracts/interfaces/IGameEntryModules.sol:IGameBetModule": "GAME_DEGENERETTE_MODULE",
  "contracts/interfaces/IGameEntryModules.sol:IGameBoonActionsModule": "GAME_BOON_MODULE",
  "contracts/interfaces/IGameActionModule.sol:IGameClaimAll": "GAME_ACTIONS_MODULE",
  "contracts/interfaces/IGameActionModule.sol:IGameClaimAmount": "GAME_ACTIONS_MODULE",
  "contracts/interfaces/IGameActionModule.sol:IGameActionModule": "GAME_ACTIONS_MODULE"
};
// These facade entries are internal in the combined Game; their split hooks
// route to Box components only in the EIP-170 profile.
if (PROFILE === "glamsterdam") {
  targets["contracts/interfaces/IGameEntryModules.sol:IGameBetModule"] = "GAME";
  targets["contracts/interfaces/IGameEntryModules.sol:IGameBoonActionsModule"] = "GAME";
}
// The five-argument purchase adapter is an internal hook in Glamsterdam;
// Game exposes the six-argument player entry (the final flag adds a foil leg).
// Keep the adapter ABI checked and fail if its required direct override disappears.
const directPurchase = "contracts/interfaces/IGameEntryModules.sol:IGamePurchaseModule";
if (PROFILE === "glamsterdam") {
  const shell = fs.readFileSync("contracts/profiles/glamsterdam/GlamsterdamGame.sol", "utf8");
  if (!/function _gamePurchase\([^]*?internal override[^]*?\{\s*_purchase\(/.test(shell)) {
    throw new Error("Glamsterdam purchase requires its direct component override");
  }
}
const files = fs.readdirSync("contracts", { recursive: true }).filter(f => f.endsWith(".sol"));
for (const [iface, key] of Object.entries(targets)) {
  if (PROFILE === "glamsterdam" && iface === directPurchase) {
    console.log(`${iface}|contracts/modules/GamePurchaseEntries.sol:GamePurchaseEntries`);
    continue;
  }
  const rows = PROFILES[PROFILE].filter(row => row.aliases.includes(key));
  if (rows.length !== 1) throw new Error(`Ambiguous host for ${iface}: ${key}`);
  const name = rows[0].contract;
  const sources = files.filter(file => path.basename(file) === `${name}.sol`);
  if (sources.length !== 1) throw new Error(`Ambiguous source for ${name}`);
  console.log(`${iface}|contracts/${sources[0]}:${name}`);
}
