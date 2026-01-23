import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
const level = await game.level();
const gameState = await game.gameState();
const totalGameETH = await ethers.provider.getBalance(deployment.contracts.GAME);

console.log("\nCurrent Game State:");
console.log("  Level:", level.toString());
console.log("  State:", gameState.toString(), "(1=SETUP, 2=PURCHASE, 3=BURN, 86=GAME_OVER)");
console.log("  Game ETH:", ethers.formatEther(totalGameETH), "ETH");
console.log("");
