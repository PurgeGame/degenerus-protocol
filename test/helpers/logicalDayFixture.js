import hre from "hardhat";
import { compiledStorageLayout } from "./storageLayout.js";

const questRoots = new Map();

export async function registerLogicalDayQuestRoot(game, quests) {
  questRoots.set((await game.getAddress()).toLowerCase(), await quests.getAddress());
}

/** Explicit header fixture for unit tests. Real lifecycle tests request and finish each round. */
export async function setPackedField(contract, name, value, contractName = "DegenerusGame") {
  const layout = await compiledStorageLayout(contractName);
  const entry = layout.storage.find((row) => row.label === name);
  if (!entry) throw new Error(`Missing packed fixture field ${contractName}.${name}`);
  const width = BigInt(layout.types[entry.type].numberOfBytes) * 8n;
  const shift = BigInt(entry.offset) * 8n;
  const address = await contract.getAddress();
  const word = BigInt(await hre.ethers.provider.getStorage(address, entry.slot));
  const mask = ((1n << width) - 1n) << shift;
  const next = (word & ~mask) | ((BigInt(value) << shift) & mask);
  await hre.network.provider.send("hardhat_setStorageAt", [address, hre.ethers.toQuantity(BigInt(entry.slot)), hre.ethers.toBeHex(next, 32)]);
}

export async function seedLogicalDay(game, day, coinflip) {
  const now = (await hre.ethers.provider.getBlock("latest")).timestamp;
  await setPackedField(game, "dailyIdx", day);
  await setPackedField(game, "dailyComplete", 1);
  await setPackedField(game, "lastDailyCompletedAt", now);
  await setPackedField(game, "lastDailyRequestWallDay", await game.currentWallDayView());
  await setPackedField(game, "_afkingResetDay", day);
  if (coinflip) {
    await setPackedField(coinflip, "requestedDailyIdx", day, "Coinflip");
    const address = await coinflip.getAddress();
    let packed = BigInt(await hre.ethers.provider.getStorage(address, 4));
    for (const offset of [4n, 7n, 10n, 13n, 19n]) {
      const shift = offset * 8n;
      packed = (packed & ~(0xffffffn << shift)) | (BigInt(day) << shift);
    }
    await hre.network.provider.send("hardhat_setStorageAt", [address, "0x4", hre.ethers.toBeHex(packed, 32)]);
    const root = "0x04343aaa474371a66bb47cad27e6432f6ed56b02c7b23c6e11e4d1818f7af200";
    const questAddress = questRoots.get((await game.getAddress()).toLowerCase());
    if (!questAddress) throw new Error("Missing selected Quests root for logical-day fixture");
    const pair = BigInt(await hre.ethers.provider.getStorage(questAddress, root));
    const mask = 0xffffffn | (0xffffffn << 64n);
    await hre.network.provider.send("hardhat_setStorageAt", [questAddress, root,
      hre.ethers.toBeHex((pair & ~mask) | BigInt(day) | (BigInt(day) << 64n), 32)]);
  }
}

/** Request and fulfill the next real logical round, including any prior midday work. */
export async function requestLogicalDay(game, signer, vrf, word) {
  const previous = await game.currentDayView_g542950();
  await hre.ethers.provider.send("evm_increaseTime", [86400]);
  await hre.ethers.provider.send("evm_mine");
  for (let i = 0; i < 300 && (await game.currentDayView_g542950()) === previous; ++i) {
    const pending = await vrf.lastRequestId();
    if (pending && !(await vrf.pendingRequests(pending))[2]) await vrf.fulfillRandomWords(pending, 777n);
    await game.connect(signer).mineRun(0xffffffff, { gasLimit: 16_777_216 });
  }
  if ((await game.currentDayView_g542950()) !== previous + 1n || !(await game.rngLocked()))
    throw new Error("next logical request did not commit");
  const id = await vrf.lastRequestId();
  await vrf.fulfillRandomWords(id, word);
  return id;
}

export async function completeLogicalDay(game, signer, vrf, word) {
  await requestLogicalDay(game, signer, vrf, word);
  for (let i = 0; i < 300 && !(await game.dailySessionState())[0]; ++i)
    await game.connect(signer).mineRun(0xffffffff, { gasLimit: 16_777_216 });
  if (!(await game.dailySessionState())[0]) throw new Error("daily read certificate did not complete");
}
