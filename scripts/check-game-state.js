import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

const level = await game.level();
const gameState = await game.gameState();

console.log("Current game state:");
console.log("  Level:", level.toString());
console.log("  State:", gameState.toString());
console.log("\nState meanings:");
console.log("  0 = INIT");
console.log("  1 = PRESALE_MINT");
console.log("  2 = PURCHASE");
console.log("  3 = JACKPOT");  
console.log("  4 = BURN");
console.log("  5 = DECIMATOR");
console.log("  6 = GAME_OVER");
