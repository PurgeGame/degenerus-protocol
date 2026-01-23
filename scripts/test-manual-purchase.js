import hre from "hardhat";
import { formatEther } from "ethers";
import deployment from "../deployment-sepolia.json" with { type: "json" };
import wallets from "../wallets.json" with { type: "json" };

const CONFIG = {
  GAS_PRICE: 52014000,
  REFERRAL_CODE: "0x0000000000000000000000000000000000000000000000000000000000000000"
};

async function main() {
  const provider = hre.ethers.provider;

  // Load player 0
  const player0 = new hre.ethers.Wallet(wallets.players[0].privateKey, provider);

  console.log(`Testing purchase with Player 0: ${player0.address}`);
  console.log(`Player 0 balance: ${formatEther(await provider.getBalance(player0.address))} ETH\n`);

  const game = await hre.ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);
  const gamepieces = await hre.ethers.getContractAt("DegenerusGamepieces", deployment.contracts.GAMEPIECES);
  // Check states
  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
  const lastPrizepool = await game.prizePoolTargetView();

  console.log(`Level: ${level}, State: ${gameState}, RNG Locked: ${rngLocked}`);
  console.log(`Mint Price: ${formatEther(priceWei)} ETH`);
  console.log(`Last Prize Pool: ${formatEther(lastPrizepool)} ETH\n`);

  // Calculate purchase (5% of last prize pool in MAPs)
  // MAPs cost 1/4 the price of player tokens
  const mapPrice = priceWei / 4n;
  const purchaseAmount = (lastPrizepool * 5n) / 100n;
  const quantity = purchaseAmount / mapPrice;
  const quantityBigInt = BigInt(Math.floor(Number(quantity)));

  console.log(`Purchase Amount: ${formatEther(purchaseAmount)} ETH`);
  console.log(`Quantity (calculated): ${quantity} MAPs`);
  console.log(`Quantity (bigint): ${quantityBigInt} MAPs\n`);

  // Calculate initiation fee
  let initiationFee = 0n;
  if (Number(level) > 3) {
    const ethMintCount = await game.ethMintLevelCount(player0.address);
    console.log(`Player ethMintLevelCount: ${ethMintCount}`);
    if (ethMintCount === 0n) {
      initiationFee = priceWei / 5n;
    }
  }

  const totalCost = (quantityBigInt * mapPrice) + initiationFee;

  console.log(`Map Price: ${mapPrice} wei (${formatEther(mapPrice)} ETH)`);
  console.log(`Initiation Fee: ${initiationFee} wei (${formatEther(initiationFee)} ETH)`);
  console.log(`Purchase Cost: ${quantityBigInt * mapPrice} wei (${formatEther(quantityBigInt * mapPrice)} ETH)`);
  console.log(`Total Cost: ${totalCost} wei (${formatEther(totalCost)} ETH)`);
  console.log(`Original Purchase Amount: ${purchaseAmount} wei (${formatEther(purchaseAmount)} ETH)\n`);

  // Try purchase
  const params = {
    quantity: quantityBigInt,
    kind: 1, // Map
    payKind: 0, // DirectEth
    payInCoin: false,
    affiliateCode: CONFIG.REFERRAL_CODE
  };

  console.log(`Purchase params:`, params);
  console.log(`Value to send: ${formatEther(totalCost)} ETH\n`);

  try {
    console.log(`Attempting purchase...`);

    // Estimate gas first
    const gasEstimate = await gamepieces.connect(player0).purchase.estimateGas(
      params,
      { value: totalCost }
    );
    console.log(`Gas estimate: ${gasEstimate.toString()}`);

    const tx = await gamepieces.connect(player0).purchase(
      params,
      { value: totalCost, gasLimit: 1000000, gasPrice: CONFIG.GAS_PRICE }
    );

    console.log(`Transaction sent: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`✅ Purchase successful! Block: ${receipt.blockNumber}`);
  } catch (e) {
    console.error(`\n❌ Purchase failed:`);
    console.error(`Error: ${e.message}`);
    if (e.data) {
      console.error(`Data: ${e.data}`);
    }
    if (e.error) {
      console.error(`Inner error: ${e.error.message || e.error}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
