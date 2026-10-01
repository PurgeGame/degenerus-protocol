import hre from "hardhat";

const layouts = new Map();

// Use the same compiled input as the running Hardhat fixture. A second Forge
// compilation at test runtime can include the whole Foundry tree and exhaust memory.
export async function compiledStorageLayout(contract = "DegenerusGame") {
  const artifact = await hre.artifacts.readArtifact(contract);
  const key = `${artifact.sourceName}:${artifact.contractName}`;
  let cached = layouts.get(key);
  if (!cached || cached.bytecode !== artifact.bytecode) {
    const promise = hre.artifacts.getBuildInfo(key).then((build) => {
      const layout = build?.output.contracts[artifact.sourceName][artifact.contractName].storageLayout;
      if (!layout) throw new Error(`Compiled storage layout missing: ${key}`);
      return layout;
    });
    cached = { bytecode: artifact.bytecode, promise };
    layouts.set(key, cached);
  }
  return cached.promise;
}

export async function compiledStorageSlot(variable) {
  const layout = await compiledStorageLayout();
  const entry = layout.storage.find((item) => item.label === variable);
  if (!entry) throw new Error(`Compiled storage field missing: ${variable}`);
  return BigInt(entry.slot);
}
