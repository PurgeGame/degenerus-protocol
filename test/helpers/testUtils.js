import hre from "hardhat";

export const ZERO_ADDRESS = "0x" + "0".repeat(40);
export const ZERO_BYTES32 = "0x" + "0".repeat(64);

// --- Time manipulation ---

export async function advanceTime(seconds) {
  await hre.ethers.provider.send("evm_increaseTime", [seconds]);
  await hre.ethers.provider.send("evm_mine");
}

export async function advanceToNextDay() {
  await advanceTime(86400);
}

export async function advanceBlocks(n) {
  for (let i = 0; i < n; i++) {
    await hre.ethers.provider.send("evm_mine");
  }
}

export async function getBlockTimestamp() {
  const block = await hre.ethers.provider.getBlock("latest");
  return block.timestamp;
}

export async function setNextTimestamp(timestamp) {
  await hre.ethers.provider.send("evm_setNextBlockTimestamp", [timestamp]);
}

// --- VRF helpers ---

export async function fulfillVRF(mockVRF, requestId, randomWord) {
  return mockVRF.fulfillRandomWords(requestId, randomWord);
}

export async function getLastVRFRequestId(mockVRF) {
  return mockVRF.lastRequestId();
}

// --- Event parsing ---

export async function getEvents(tx, contract, eventName) {
  const receipt = await tx.wait();
  return receipt.logs
    .map((log) => {
      try {
        return contract.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .filter((e) => e && e.name === eventName);
}

export async function getEvent(tx, contract, eventName) {
  const events = await getEvents(tx, contract, eventName);
  if (events.length === 0) {
    throw new Error(`Event ${eventName} not found in transaction`);
  }
  return events[0];
}

// --- Convenience ---

export function eth(n) {
  return hre.ethers.parseEther(String(n));
}

export function formatEth(wei) {
  return hre.ethers.formatEther(wei);
}
