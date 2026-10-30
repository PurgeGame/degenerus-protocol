import hre from "hardhat";

// The wrapper inherits a complete production module and exceeds deployment limits.
// These tests call only its pure math entry points, which need no constructor state.
// Install the compiled test runtime; production deployments still enforce size limits.
export async function degeneretteMathFixture() {
  const address = hre.ethers.toBeHex(0x2610002n, 20);
  const { deployedBytecode } = await hre.artifacts.readArtifact("DegeneretteMathHarness");
  await hre.network.provider.send("hardhat_setCode", [address, deployedBytecode]);
  return hre.ethers.getContractAt("DegeneretteMathHarness", address);
}
