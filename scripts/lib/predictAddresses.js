import { ethers } from "ethers";

// 22:57 UTC in seconds — matches GameTimeLib.JACKPOT_RESET_TIME
const JACKPOT_RESET_TIME = 82620n;

/**
 * Contract deployment order. Each entry maps to a ContractAddresses.sol constant.
 * Order is critical — contracts with constructor-time cross-contract calls
 * must appear AFTER their dependencies.
 *
 * Constraints:
 *  - COIN (N+12) before VAULT (N+21): vault reads vaultMintAllowance()
 *  - GAME (N+14) + modules (N+1..11) before SDGNRS (N+22): staked calls initPerpetualTickets; vault/staked
 *    constructors self-subscribe via the game-resident afking path (game.subscribe, SUB-09)
 *  - GAME_AFKING_MODULE (N+11) before VAULT (N+21) / SDGNRS (N+22): the v55 afking surface is
 *    game-resident (DegenerusGame delegatecalls GameAfkingModule); the vault/staked constructor
 *    self-subscribes hit live module code only if GAME + the afking module are deployed first.
 *    Both new modules are constructor-arg-less delegatecall modules (like the other 10) — no
 *    upstream dependency of their own; placed in the game-module block so source-order ≡ DEPLOY_ORDER
 *    ≡ the patched ContractAddresses.sol constant order (GAME_BINGO_MODULE :33 / GAME_AFKING_MODULE :35).
 *  - SDGNRS (N+22) before DGNRS (N+23): DGNRS reads SDGNRS balance
 *  - GAME (N+14) before ADMIN (N+24): admin calls wireVrf()
 *  - GNRUS (N+25) last: no constructor cross-calls, reads compile-time constants only
 *
 * v55.0 note: the standalone AfKing contract (old AF_KING key at the former N+18) was DISSOLVED — its
 * subscriber state + logic folded into DegenerusGame (GameAfkingModule). That key is removed here; the
 * two new game modules GAME_BINGO_MODULE + GAME_AFKING_MODULE are inserted in the game-module block.
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
  "GAME_BINGO_MODULE",     // N+10: DegenerusGameBingoModule (no ctor args; claimBingo + ARCH-04 reclaim)
  "GAME_AFKING_MODULE",    // N+11: GameAfkingModule (no ctor args; game-resident afking surface; must precede VAULT/SDGNRS subscribe)
  "COIN",                  // N+12: FLIP
  "COINFLIP",              // N+13: Coinflip (no constructor args)
  "GAME",                  // N+14: DegenerusGame (internal storage only)
  "WWXRP",                 // N+15: WrappedWrappedXRP
  "AFFILIATE",             // N+16: DegenerusAffiliate
  "JACKPOTS",              // N+17: DegenerusJackpots
  "QUESTS",                // N+18: DegenerusQuests
  "DEITY_PASS",            // N+19: DegenerusDeityPass
  "VAULT",                 // N+20: DegenerusVault (calls COIN; constructor self-subscribes via game.subscribe)
  "SDGNRS",                // N+21: sDGNRS (calls GAME; constructor self-subscribes via game.subscribe; mints to DGNRS)
  "DGNRS",                 // N+22: DGNRS (reads SDGNRS balance)
  "ADMIN",                 // N+23: DegenerusAdmin (calls VRF + GAME)
  "GNRUS",                 // N+24: GNRUS (self-mint only, no cross-calls)
  // v71.0: foil pack game-resident delegatecall module. Appended LAST so adding it
  // does not shift any existing predicted address (the auto-subscribed VAULT/SDGNRS
  // addresses feed trait derivation; keeping them fixed avoids perturbing RNG). It
  // has no ctor args and no deploy-time dependents — only GAME's runtime delegatecalls.
  "GAME_FOILPACK_MODULE",  // N+25: DegenerusGameFoilPackModule
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
  GAME_BINGO_MODULE: "DegenerusGameBingoModule",
  GAME_AFKING_MODULE: "GameAfkingModule",
  COIN: "FLIP",
  COINFLIP: "Coinflip",
  GAME: "DegenerusGame",
  WWXRP: "WrappedWrappedXRP",
  AFFILIATE: "DegenerusAffiliate",
  JACKPOTS: "DegenerusJackpots",
  QUESTS: "DegenerusQuests",
  DEITY_PASS: "DegenerusDeityPass",
  VAULT: "DegenerusVault",
  SDGNRS: "sDGNRS",
  DGNRS: "DGNRS",
  ADMIN: "DegenerusAdmin",
  GNRUS: "GNRUS",
  GAME_FOILPACK_MODULE: "DegenerusGameFoilPackModule",
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
