import hre from "hardhat";

// This harness inherits the full production module and adds a pure test entry point.
// Its wrapper can cross EIP-170 even while the production module fits. Install only
// the test runtime at a synthetic address; retain the network's deployment-size
// enforcement for every production contract. The picker needs no constructor state.
export async function jackpotSoloFixture() {
  const address = hre.ethers.toBeHex(0x2610001n, 20);
  const { deployedBytecode } = await hre.artifacts.readArtifact("JackpotSoloTester");
  await hre.network.provider.send("hardhat_setCode", [address, deployedBytecode]);
  return { tester: await hre.ethers.getContractAt("JackpotSoloTester", address) };
}
