// Smoke test: prove connection.js loads the live deployment and reads core views.
import { loadConfig } from "../src/config.js";
import { Connection } from "../src/connection.js";

const cfg = loadConfig({ mode: "local" });
const c = new Connection(cfg);
console.log("chainId:", await c.chainId());
console.log("GAME addr:", c.address("GAME"));
console.log("merged GAME abi fragments:", c.abi("GAME").length);

const g = c.game;
const [lvl, jp, lastDay, locked, price] = await g.purchaseInfo();
console.log("purchaseInfo:", { lvl: Number(lvl), jackpotPhase: jp, lastPurchaseDay: lastDay, rngLocked: locked, priceWei: price.toString() });
console.log("level:", Number(await g.level()));
console.log("gameOver:", await g.gameOver());
console.log("mintPrice:", (await g.mintPrice()).toString());
console.log("claimablePoolView:", (await g.claimablePoolView()).toString());
console.log("currentPrizePoolView:", (await g.currentPrizePoolView()).toString());
console.log("nextPrizePoolView:", (await g.nextPrizePoolView()).toString());
console.log("futurePrizePoolView:", (await g.futurePrizePoolView()).toString());
console.log("yieldAccumulatorView:", (await g.yieldAccumulatorView()).toString());

// stETH backing read
const steth = new (await import("ethers")).ethers.Contract(
  c.stethAddress, ["function balanceOf(address) view returns (uint256)"], c.provider);
console.log("stETH.balanceOf(game):", (await steth.balanceOf(c.address("GAME"))).toString());
console.log("game ETH balance:", (await c.provider.getBalance(c.address("GAME"))).toString());

// token handles
console.log("FLIP totalSupply:", (await c.coin.totalSupply()).toString());
console.log("sDGNRS totalSupply:", (await c.sdgnrs.totalSupply()).toString());
console.log("OK: connection smoke passed");
