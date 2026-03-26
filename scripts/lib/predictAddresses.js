import { ethers } from "ethers";

// 22:57 UTC in seconds — matches GameTimeLib.JACKPOT_RESET_TIME
const JACKPOT_RESET_TIME = 82620n;

/**
 * Contract deployment order. Each entry maps to a ContractAddresses.sol constant.
 * Order is critical — contracts with constructor-time cross-contract calls
 * must appear AFTER their dependencies.
 *
 * Constraints:
 *  - COIN (N+11) before VAULT (N+19): vault reads vaultMintAllowance()
 *  - GAME (N+13) + modules (N+1..10) before SDGNRS (N+20): stonk calls claimWhalePass/setAfKingMode
 *  - SDGNRS (N+20) before DGNRS (N+21): DGNRS reads SDGNRS balance
 *  - GAME (N+13) before ADMIN (N+22): admin calls wireVrf()
 *  - GNRUS (N+23) last: no constructor cross-calls, reads compile-time constants only
 */
export const DEPLOY_ORDER = [
  "ICONS_32",              // N+0:  Icons32Data
  "GAME_MINT_MODULE",      // N+1:  DegenerusGameMintModule
  "GAME_ADVANCE_MODULE",   // N+2:  DegenerusGameAdvanceModule
  "GAME_WHALE_MODULE",     // N+3:  DegenerusGameWhaleModule
  "GAME_JACKPOT_MODULE",   // N+4:  DegenerusGameJackpotModule
  "GAME_DECIMATOR_MODULE", // N+5:  DegenerusGameDecimatorModule
  "GAME_ENDGAME_MODULE",   // N+6:  DegenerusGameEndgameModule
  "GAME_GAMEOVER_MODULE",  // N+7:  DegenerusGameGameOverModule
  "GAME_LOOTBOX_MODULE",   // N+8:  DegenerusGameLootboxModule
  "GAME_BOON_MODULE",      // N+9:  DegenerusGameBoonModule
  "GAME_DEGENERETTE_MODULE", // N+10: DegenerusGameDegeneretteModule
  "COIN",                  // N+11: BurnieCoin
  "COINFLIP",              // N+12: BurnieCoinflip (immutable args only)
  "GAME",                  // N+13: DegenerusGame (internal storage only)
  "WWXRP",                 // N+14: WrappedWrappedXRP
  "AFFILIATE",             // N+15: DegenerusAffiliate
  "JACKPOTS",              // N+16: DegenerusJackpots
  "QUESTS",                // N+17: DegenerusQuests
  "DEITY_PASS",            // N+18: DegenerusDeityPass
  "VAULT",                 // N+19: DegenerusVault (calls COIN)
  "SDGNRS",                // N+20: StakedDegenerusStonk (calls GAME, mints to DGNRS)
  "DGNRS",                 // N+21: DegenerusStonk (reads SDGNRS balance)
  "ADMIN",                 // N+22: DegenerusAdmin (calls VRF + GAME)
  "GNRUS",                 // N+23: DegenerusCharity (self-mint only, no cross-calls)
];

/**
 * Map from ContractAddresses constant name to Solidity contract name.
 */
export const KEY_TO_CONTRACT = {
  ICONS_32: "Icons32Data",
  GAME_MINT_MODULE: "DegenerusGameMintModule",
  GAME_ADVANCE_MODULE: "DegenerusGameAdvanceModule",
  GAME_WHALE_MODULE: "DegenerusGameWhaleModule",
  GAME_JACKPOT_MODULE: "DegenerusGameJackpotModule",
  GAME_DECIMATOR_MODULE: "DegenerusGameDecimatorModule",
  GAME_ENDGAME_MODULE: "DegenerusGameEndgameModule",
  GAME_GAMEOVER_MODULE: "DegenerusGameGameOverModule",
  GAME_LOOTBOX_MODULE: "DegenerusGameLootboxModule",
  GAME_BOON_MODULE: "DegenerusGameBoonModule",
  GAME_DEGENERETTE_MODULE: "DegenerusGameDegeneretteModule",
  COIN: "BurnieCoin",
  COINFLIP: "BurnieCoinflip",
  GAME: "DegenerusGame",
  WWXRP: "WrappedWrappedXRP",
  AFFILIATE: "DegenerusAffiliate",
  JACKPOTS: "DegenerusJackpots",
  QUESTS: "DegenerusQuests",
  DEITY_PASS: "DegenerusDeityPass",
  VAULT: "DegenerusVault",
  SDGNRS: "StakedDegenerusStonk",
  DGNRS: "DegenerusStonk",
  ADMIN: "DegenerusAdmin",
  GNRUS: "DegenerusCharity",
};

/**
 * Predict CREATE addresses for the full deployment sequence.
 * @param {string} deployerAddress - Deployer EOA address
 * @param {number} startingNonce - Deployer's current nonce
 * @returns {Map<string, string>} Map from constant name to predicted address
 */
export function predictAddresses(deployerAddress, startingNonce) {
  const addresses = new Map();
  for (let i = 0; i < DEPLOY_ORDER.length; i++) {
    const addr = ethers.getCreateAddress({
      from: deployerAddress,
      nonce: startingNonce + i,
    });
    addresses.set(DEPLOY_ORDER[i], addr);
  }
  return addresses;
}

/**
 * Compute DEPLOY_DAY_BOUNDARY from a deployment timestamp.
 * Matches GameTimeLib: day = (timestamp - JACKPOT_RESET_TIME) / 86400
 * @param {number} deployTimestamp - Unix timestamp in seconds
 * @returns {number} Day boundary as uint48
 */
export function computeDeployDayBoundary(deployTimestamp) {
  const ts = BigInt(deployTimestamp);
  return Number((ts - JACKPOT_RESET_TIME) / 86400n);
}
