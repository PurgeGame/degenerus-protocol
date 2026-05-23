import { ethers } from "ethers";

// 22:57 UTC in seconds — matches GameTimeLib.JACKPOT_RESET_TIME
const JACKPOT_RESET_TIME = 82620n;

/**
 * Contract deployment order. Each entry maps to a ContractAddresses.sol constant.
 * Order is critical — contracts with constructor-time cross-contract calls
 * must appear AFTER their dependencies.
 *
 * Constraints:
 *  - COIN (N+10) before VAULT (N+19): vault reads vaultMintAllowance()
 *  - GAME (N+12) + modules (N+1..9) before SDGNRS (N+20): stonk calls claimWhalePass/setAfKingMode
 *  - AFKING (N+18) before VAULT (N+19) / SDGNRS (N+20): their constructors call afKing.subscribe()
 *    (AfKing's own constructor makes no cross-contract calls — sets 3 immutables only — so it has
 *    no upstream dependency; placed right before VAULT to minimize the downstream address shift)
 *  - SDGNRS (N+20) before DGNRS (N+21): DGNRS reads SDGNRS balance
 *  - GAME (N+12) before ADMIN (N+22): admin calls wireVrf()
 *  - GNRUS (N+23) last: no constructor cross-calls, reads compile-time constants only
 */
export const DEPLOY_ORDER = [
  "ICONS_32",              // N+0:  Icons32Data
  "GAME_MINT_MODULE",      // N+1:  DegenerusGameMintModule
  "GAME_ADVANCE_MODULE",   // N+2:  DegenerusGameAdvanceModule
  "GAME_WHALE_MODULE",     // N+3:  DegenerusGameWhaleModule
  "GAME_JACKPOT_MODULE",   // N+4:  DegenerusGameJackpotModule
  "GAME_DECIMATOR_MODULE", // N+5:  DegenerusGameDecimatorModule
  "GAME_GAMEOVER_MODULE",  // N+6:  DegenerusGameGameOverModule
  "GAME_LOOTBOX_MODULE",   // N+7:  DegenerusGameLootboxModule
  "GAME_BOON_MODULE",      // N+8:  DegenerusGameBoonModule
  "GAME_DEGENERETTE_MODULE", // N+9:  DegenerusGameDegeneretteModule
  "COIN",                  // N+10: BurnieCoin
  "COINFLIP",              // N+11: BurnieCoinflip (no constructor args)
  "GAME",                  // N+12: DegenerusGame (internal storage only)
  "WWXRP",                 // N+13: WrappedWrappedXRP
  "AFFILIATE",             // N+14: DegenerusAffiliate
  "JACKPOTS",              // N+15: DegenerusJackpots
  "QUESTS",                // N+16: DegenerusQuests
  "DEITY_PASS",            // N+17: DegenerusDeityPass
  "AF_KING",               // N+18: AfKing (no cross-calls; must precede VAULT/SDGNRS subscribe)
  "VAULT",                 // N+19: DegenerusVault (calls COIN; calls AF_KING.subscribe)
  "SDGNRS",                // N+20: StakedDegenerusStonk (calls GAME, AF_KING.subscribe; mints to DGNRS)
  "DGNRS",                 // N+21: DegenerusStonk (reads SDGNRS balance)
  "ADMIN",                 // N+22: DegenerusAdmin (calls VRF + GAME)
  "GNRUS",                 // N+23: GNRUS (self-mint only, no cross-calls)
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
  AF_KING: "AfKing",
  VAULT: "DegenerusVault",
  SDGNRS: "StakedDegenerusStonk",
  DGNRS: "DegenerusStonk",
  ADMIN: "DegenerusAdmin",
  GNRUS: "GNRUS",
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
